// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/wepublic"
import topbar from "../vendor/topbar"
import { renderNeighborhood } from "./neighborhood"

// Neighborhood LiveView hook
const Neighborhood = {
  mounted() {
    this.initScene()

    // Listen for user updates from server
    this.handleEvent("update_users", ({ users }) => {
      if (this.updateUsers) {
        this.updateUsers(users)
      }
    })

    // Listen for world state updates
    this.handleEvent("world_update", ({ entities }) => {
      if (this.updateEntities) {
        this.updateEntities(entities)
      }
    })

    // Listen for position updates from other users
    this.handleEvent("user_position", ({ user_id, position }) => {
      if (this.updateUserPosition) {
        this.updateUserPosition(user_id, position)
      }
    })

    // Listen for pan-to-position requests (e.g., clicking a connection)
    this.handleEvent("pan_to_position", ({ x, z }) => {
      if (this.panToPosition) {
        this.panToPosition(x, z)
      }
    })

    // Listen for location changes (travel)
    this.handleEvent("location_changed", ({ location, objects }) => {
      if (this.updateLocation) {
        this.updateLocation(location)
      }
      // Clear and re-add all objects for new location
      if (objects && this.addWorldObject) {
        objects.forEach(obj => this.addWorldObject(obj))
      }
    })

    // Listen for object placement
    this.handleEvent("object_placed", ({ object }) => {
      if (this.addWorldObject) {
        this.addWorldObject(object)
      }
    })

    // Listen for object updates
    this.handleEvent("object_updated", ({ object }) => {
      if (this.updateWorldObject) {
        this.updateWorldObject(object)
      }
    })

    // Listen for place mode toggle
    this.handleEvent("set_place_mode", ({ enabled }) => {
      if (this.setPlaceMode) {
        this.setPlaceMode(enabled)
      }
    })
  },

  initScene() {
    // Parse configuration from data attributes
    const config = {
      users: JSON.parse(this.el.dataset.users || "[]"),
      currentUserId: this.el.dataset.currentUserId || null,
      connections: JSON.parse(this.el.dataset.connections || "[]"),
      onUserClick: (user) => {
        this.pushEvent("user_clicked", { user_id: user.id })
      },
      onMove: (direction) => {
        // Send movement intent to server
        this.pushEvent("move", { direction: direction })
      },
      onMoveTo: (x, z) => {
        // Send click-to-move intent to server
        this.pushEvent("move_to", { x: x, z: z })
      },
      onPlaceObject: (x, z) => {
        // Send place object intent to server
        this.pushEvent("place_object", { x: x, z: z })
      }
    }

    const result = renderNeighborhood(this.el.id, config)
    if (result) {
      this.cleanup = result.cleanup
      this.updateUsers = result.updateUsers
      this.updateEntities = result.updateEntities
      this.updateUserPosition = result.updateUserPosition
      this.panToPosition = result.panToPosition
      this.updateLocation = result.updateLocation
      this.addWorldObject = result.addWorldObject
      this.updateWorldObject = result.updateWorldObject
      this.setPlaceMode = result.setPlaceMode
      this.sceneInitialized = true
    }
  },

  updated() {
    // Re-initialize if the canvas was somehow removed
    const canvas = this.el.querySelector("canvas")
    if (!canvas && this.sceneInitialized) {
      this.initScene()
    }
  },

  destroyed() {
    if (this.cleanup) {
      this.cleanup()
    }
  }
}

// Expose for non-LiveView usage
window.neighborhood = (options) => renderNeighborhood("neighborhood-container", options)

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Neighborhood},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

