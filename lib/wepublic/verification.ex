defmodule Wepublic.Verification do
  @moduledoc """
  Handles verification of user web identities.

  Supports:
  - DID verification (did:web) - checks for verification token in DID document
  - Feed verification (RSS/Atom) - validates feed URL and extracts metadata
  """

  alias Wepublic.Repo
  alias Wepublic.Accounts.User

  @doc """
  Verifies a user's DID by fetching their DID document and checking for the verification token.

  For did:web:example.com, fetches https://example.com/.well-known/did.json
  For did:web:example.com:path, fetches https://example.com/path/did.json
  """
  def verify_did(%User{} = user) do
    with {:ok, did} <- validate_did_format(user.did),
         {:ok, url} <- did_to_url(did),
         {:ok, document} <- fetch_did_document(url),
         :ok <- verify_token_in_document(document, user.did_verification_token) do
      user
      |> User.did_verified_changeset()
      |> Repo.update()
    end
  end

  @doc """
  Verifies a user's feed by fetching and parsing it.
  Extracts the feed title and validates it's a proper RSS/Atom feed.
  """
  def verify_feed(%User{} = user) do
    with {:ok, url} <- validate_feed_url(user.feed_url),
         {:ok, feed_data} <- fetch_and_parse_feed(url) do
      user
      |> User.feed_verified_changeset(feed_data.title)
      |> Repo.update()
    end
  end

  @doc """
  Fetches a verified user's feed and returns parsed items.
  Returns items with: title, link, published_at, summary, is_product (boolean)
  """
  def fetch_feed_items(%User{feed_verified_at: nil}), do: {:error, :feed_not_verified}

  def fetch_feed_items(%User{feed_url: url}) when is_binary(url) do
    with {:ok, feed_data} <- fetch_and_parse_feed(url) do
      {:ok, feed_data.items}
    end
  end

  @doc """
  Checks if any feed items appear to be products/services for sale.
  Looks for price indicators, buy links, or commerce-related content.
  """
  def has_items_for_sale?(%User{} = user) do
    case fetch_feed_items(user) do
      {:ok, items} -> Enum.any?(items, &is_product_item?/1)
      _ -> false
    end
  end

  # Private functions

  defp validate_did_format(nil), do: {:error, :no_did}

  defp validate_did_format(did) do
    if String.match?(did, ~r/^did:web:.+$/) do
      {:ok, did}
    else
      {:error, :invalid_did_format}
    end
  end

  defp did_to_url("did:web:" <> domain_path) do
    # Handle URL-encoded characters
    decoded = URI.decode(domain_path)

    # Split domain from path (colons become slashes in path)
    parts = String.split(decoded, ":")

    case parts do
      [domain] ->
        {:ok, "https://#{domain}/.well-known/did.json"}

      [domain | path_parts] ->
        path = Enum.join(path_parts, "/")
        {:ok, "https://#{domain}/#{path}/did.json"}
    end
  end

  defp fetch_did_document(url) do
    case http_client().get(url) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, document} -> {:ok, document}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end

  defp verify_token_in_document(document, expected_token) do
    # Look for the token in alsoKnownAs, service endpoints, or a custom verification field
    document_json = Jason.encode!(document)

    if String.contains?(document_json, expected_token) do
      :ok
    else
      {:error, :token_not_found}
    end
  end

  defp validate_feed_url(nil), do: {:error, :no_feed_url}

  defp validate_feed_url(url) do
    if String.match?(url, ~r/^https?:\/\/.+/) do
      {:ok, url}
    else
      {:error, :invalid_feed_url}
    end
  end

  defp fetch_and_parse_feed(url) do
    case http_client().get(url) do
      {:ok, %{status: 200, body: body}} ->
        parse_feed(body)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end

  defp parse_feed(body) do
    # Try RSS first, then Atom
    cond do
      String.contains?(body, "<rss") or String.contains?(body, "<channel>") ->
        parse_rss(body)

      String.contains?(body, "<feed") and String.contains?(body, "xmlns=\"http://www.w3.org/2005/Atom\"") ->
        parse_atom(body)

      String.contains?(body, "<feed") ->
        parse_atom(body)

      true ->
        {:error, :unknown_feed_format}
    end
  end

  defp parse_rss(body) do
    try do
      {:ok, doc} = parse_xml(body)

      title =
        doc
        |> xpath("//channel/title/text()")
        |> to_string()
        |> String.trim()

      items =
        doc
        |> xpath("//item")
        |> Enum.map(&parse_rss_item/1)

      {:ok, %{title: title, items: items}}
    rescue
      _ -> {:error, :parse_failed}
    end
  end

  defp parse_atom(body) do
    try do
      {:ok, doc} = parse_xml(body)

      title =
        doc
        |> xpath("//feed/title/text()")
        |> to_string()
        |> String.trim()

      items =
        doc
        |> xpath("//entry")
        |> Enum.map(&parse_atom_entry/1)

      {:ok, %{title: title, items: items}}
    rescue
      _ -> {:error, :parse_failed}
    end
  end

  defp parse_rss_item(item) do
    title = xpath_text(item, "./title")
    link = xpath_text(item, "./link")
    description = xpath_text(item, "./description")
    pub_date = xpath_text(item, "./pubDate")

    %{
      title: title,
      link: link,
      summary: description,
      published_at: parse_date(pub_date),
      is_product: is_product_item?(%{title: title, summary: description, link: link})
    }
  end

  defp parse_atom_entry(entry) do
    title = xpath_text(entry, "./title")
    link = xpath_attr(entry, "./link", "href")
    summary = xpath_text(entry, "./summary") || xpath_text(entry, "./content")
    published = xpath_text(entry, "./published") || xpath_text(entry, "./updated")

    %{
      title: title,
      link: link,
      summary: summary,
      published_at: parse_date(published),
      is_product: is_product_item?(%{title: title, summary: summary, link: link})
    }
  end

  defp is_product_item?(item) do
    text = "#{item[:title]} #{item[:summary]} #{item[:link]}" |> String.downcase()

    product_indicators = [
      "buy",
      "purchase",
      "order",
      "shop",
      "store",
      "product",
      "price",
      "$",
      "€",
      "£",
      "for sale",
      "checkout",
      "add to cart",
      "gumroad",
      "shopify",
      "etsy",
      "patreon",
      "ko-fi",
      "paypal"
    ]

    Enum.any?(product_indicators, &String.contains?(text, &1))
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) do
    # Try common date formats
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        datetime

      _ ->
        # Try RFC 2822 format (common in RSS)
        parse_rfc2822(date_string)
    end
  end

  defp parse_rfc2822(_date_string) do
    # Simplified RFC 2822 parsing
    # Full implementation would use a library like Timex
    # For now, return nil to indicate unparseable date
    nil
  end

  # Simple XML parsing helpers using erlang's xmerl
  defp parse_xml(body) do
    try do
      {doc, _} =
        body
        |> String.to_charlist()
        |> :xmerl_scan.string(quiet: true)

      {:ok, doc}
    rescue
      _ -> {:error, :invalid_xml}
    catch
      :exit, _ -> {:error, :invalid_xml}
    end
  end

  defp xpath(doc, path) do
    try do
      :xmerl_xpath.string(String.to_charlist(path), doc)
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  defp xpath_text(doc, path) do
    case xpath(doc, "#{path}/text()") do
      [{:xmlText, _, _, _, text, _} | _] -> to_string(text) |> String.trim()
      _ -> nil
    end
  end

  defp xpath_attr(doc, path, attr) do
    nodes = xpath(doc, path)

    case nodes do
      [node | _] ->
        case :xmerl_xpath.string(String.to_charlist("@#{attr}"), node) do
          [{:xmlAttribute, _, _, _, _, _, _, _, value, _} | _] ->
            to_string(value)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  # HTTP client wrapper for testing
  defp http_client do
    Application.get_env(:wepublic, :http_client, Wepublic.HTTPClient)
  end
end
