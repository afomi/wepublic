defmodule Wepublic.HTTPClient do
  @moduledoc """
  HTTP client wrapper for external requests.
  Uses Req library for HTTP requests.
  """

  def get(url, opts \\ []) do
    case Req.get(url, opts) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def post(url, body, opts \\ []) do
    case Req.post(url, [body: body] ++ opts) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
