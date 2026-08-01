import * as maplibregl from "maplibre-gl"

const categoryColors = [
  "match", ["get", "category"],
  "eligible", "#10b981",
  "free", "#06b6d4",
  "pending_analysis", "#fbbf24",
  "under_analysis", "#f97316",
  "not_eligible", "#a8a29e",
  "awarded", "#ff5d39",
  "#ff5d39",
]

const brazilianStates = [
  ["AC", "Acre"], ["AL", "Alagoas"], ["AP", "Amapá"], ["AM", "Amazonas"],
  ["BA", "Bahia"], ["CE", "Ceará"], ["DF", "Distrito Federal"], ["ES", "Espírito Santo"],
  ["GO", "Goiás"], ["MA", "Maranhão"], ["MT", "Mato Grosso"], ["MS", "Mato Grosso do Sul"],
  ["MG", "Minas Gerais"], ["PA", "Pará"], ["PB", "Paraíba"], ["PR", "Paraná"],
  ["PE", "Pernambuco"], ["PI", "Piauí"], ["RJ", "Rio de Janeiro"],
  ["RN", "Rio Grande do Norte"], ["RS", "Rio Grande do Sul"], ["RO", "Rondônia"],
  ["RR", "Roraima"], ["SC", "Santa Catarina"], ["SP", "São Paulo"], ["SE", "Sergipe"],
  ["TO", "Tocantins"],
]

const layerPreferenceKey = "jazida.map.layers.v1"
const defaultLayerPreferences = {
  basemap: "street",
  mining: true,
  states: true,
  miningOpacity: 1,
}

const miningLayerIds = ["mining-clusters", "mining-polygons", "mining-polygons-hover"]
const stateLayerIds = [
  "brazil-states-selected",
  "brazil-states-boundaries",
  "brazil-states-selected-boundary",
  "brazil-states-labels",
]

const readLayerPreferences = satelliteAvailable => {
  try {
    const stored = JSON.parse(window.localStorage.getItem(layerPreferenceKey))
    if (!stored || typeof stored !== "object") return {...defaultLayerPreferences}

    return {
      basemap: stored.basemap === "satellite" && satelliteAvailable ? "satellite" : "street",
      mining: typeof stored.mining === "boolean" ? stored.mining : true,
      states: typeof stored.states === "boolean" ? stored.states : true,
      miningOpacity: typeof stored.miningOpacity === "number" && Number.isFinite(stored.miningOpacity)
        ? Math.min(1, Math.max(0.3, stored.miningOpacity))
        : 1,
    }
  } catch (_error) {
    return {...defaultLayerPreferences}
  }
}

const MiningMap = {
  mounted() {
    const style = this.el.dataset.styleUrl
    const tileTemplate = `${window.location.origin}${this.el.dataset.tileUrl}`
    this.satelliteTilejsonUrl = this.el.dataset.satelliteTilejsonUrl
    this.statesUrlTemplate = this.el.dataset.statesUrlTemplate
    this.abortController = new AbortController()
    this.layerPreferences = readLayerPreferences(Boolean(this.satelliteTilejsonUrl))
    this.setupLayerControl()
    this.saveLayerPreferences()

    this.map = new maplibregl.Map({
      container: this.el,
      style,
      center: [-51.7, -14.2],
      zoom: 3.5,
      minZoom: 2.5,
      maxZoom: 14,
      attributionControl: false,
    })

    this.map.addControl(new maplibregl.NavigationControl({showCompass: false}), "bottom-right")
    this.map.addControl(new maplibregl.AttributionControl({compact: true}), "bottom-left")

    this.map.on("error", event => {
      if (event.sourceId === "satellite-basemap") {
        this.handleSatelliteError()
        return
      }

      console.error("MapLibre error", event.error)
      const loading = this.el.querySelector("[data-map-loading]")
      if (loading) loading.textContent = "Não foi possível carregar o mapa. Use a lista para explorar."
    })

    this.map.once("style.load", () => {
      this.map.addSource("mining-areas", {
        type: "vector",
        tiles: [tileTemplate],
        minzoom: 0,
        maxzoom: 14,
      })

      this.map.addLayer({
        id: "mining-clusters",
        type: "circle",
        source: "mining-areas",
        "source-layer": "areas",
        maxzoom: 7,
        paint: {
          "circle-color": categoryColors,
          "circle-radius": ["interpolate", ["linear"], ["get", "count"], 1, 4, 100, 10, 1000, 18],
          "circle-opacity": 0.8,
          "circle-stroke-color": "#fffdf8",
          "circle-stroke-width": 1.5,
        },
      })

      this.map.addLayer({
        id: "mining-polygons",
        type: "fill",
        source: "mining-areas",
        "source-layer": "areas",
        minzoom: 7,
        paint: {
          "fill-color": categoryColors,
          "fill-opacity": ["interpolate", ["linear"], ["zoom"], 7, 0.45, 12, 0.68],
          "fill-outline-color": "#fffdf8",
        },
      })

      this.map.addLayer({
        id: "mining-polygons-hover",
        type: "line",
        source: "mining-areas",
        "source-layer": "areas",
        minzoom: 7,
        paint: {"line-color": "#183128", "line-width": 2},
        filter: ["==", ["get", "id"], -1],
      })

      this.loadStateMarkings()
      this.el.querySelector("[data-map-loading]")?.remove()
      this.applyFilters()
      this.applyLayerPreferences()
    })

    this.map.on("sourcedata", event => {
      if (
        event.sourceId === "satellite-basemap" &&
        event.isSourceLoaded &&
        this.layerPreferences.basemap === "satellite"
      ) {
        this.setLayerStatus("")
      }
    })

    this.map.on("mousemove", "mining-polygons", event => {
      const feature = event.features?.[0]
      this.map.getCanvas().style.cursor = feature ? "pointer" : ""
      if (feature) this.map.setFilter("mining-polygons-hover", ["==", ["get", "id"], feature.properties.id])
    })

    this.map.on("mouseleave", "mining-polygons", () => {
      this.map.getCanvas().style.cursor = ""
      this.map.setFilter("mining-polygons-hover", ["==", ["get", "id"], -1])
    })

    this.map.on("click", "mining-polygons", event => {
      const feature = event.features?.[0]
      if (feature?.properties?.id) this.pushEvent("select_process", {id: feature.properties.id})
    })

    this.handleEvent("map:filters", filters => {
      this.filters = filters
      this.applyFilters()
    })
  },

  applyFilters() {
    if (this.map?.getLayer("mining-polygons")) {
      const clauses = []
      if (this.filters?.category) clauses.push(["==", ["get", "category"], this.filters.category])
      if (this.filters?.state) clauses.push(["==", ["get", "state_code"], this.filters.state.toUpperCase()])
      const filter = clauses.length === 0 ? null : ["all", ...clauses]
      this.map.setFilter("mining-polygons", filter)
      this.map.setFilter("mining-clusters", this.filters?.category ? ["==", ["get", "category"], this.filters.category] : null)
    }

    this.applyStateFilter()
  },

  async loadStateMarkings() {
    if (!this.statesUrlTemplate) return

    try {
      const stateCollections = await Promise.all(brazilianStates.map(async ([code, name]) => {
        const url = this.statesUrlTemplate.replace("{state}", code)
        const response = await fetch(url, {signal: this.abortController.signal})
        if (!response.ok) throw new Error(`IBGE ${code}: HTTP ${response.status}`)

        const collection = await response.json()
        return collection.features.map(feature => ({
          ...feature,
          properties: {...feature.properties, state_code: code, state_name: name},
        }))
      }))

      if (!this.map || this.map.getSource("brazil-states")) return

      this.map.addSource("brazil-states", {
        type: "geojson",
        attribution: "Malhas territoriais © IBGE",
        data: {type: "FeatureCollection", features: stateCollections.flat()},
      })

      const beforeId = this.map.getLayer("mining-clusters") ? "mining-clusters" : undefined

      this.map.addLayer({
        id: "brazil-states-selected",
        type: "fill",
        source: "brazil-states",
        maxzoom: 8,
        paint: {"fill-color": "#f4c95d", "fill-opacity": 0.16},
        filter: ["==", ["get", "state_code"], "__none__"],
      }, beforeId)

      this.map.addLayer({
        id: "brazil-states-boundaries",
        type: "line",
        source: "brazil-states",
        maxzoom: 10,
        paint: {
          "line-color": "#31584b",
          "line-opacity": ["interpolate", ["linear"], ["zoom"], 2.5, 0.38, 7, 0.7],
          "line-width": ["interpolate", ["linear"], ["zoom"], 2.5, 0.75, 7, 1.4],
          "line-dasharray": [3, 2],
        },
      }, beforeId)

      this.map.addLayer({
        id: "brazil-states-selected-boundary",
        type: "line",
        source: "brazil-states",
        maxzoom: 10,
        paint: {"line-color": "#183128", "line-opacity": 0.92, "line-width": 2.4},
        filter: ["==", ["get", "state_code"], "__none__"],
      }, beforeId)

      this.map.addLayer({
        id: "brazil-states-labels",
        type: "symbol",
        source: "brazil-states",
        minzoom: 2.5,
        maxzoom: 7.5,
        layout: {
          "text-field": ["get", "state_code"],
          "text-size": ["interpolate", ["linear"], ["zoom"], 2.5, 9, 6, 12],
          "text-letter-spacing": 0.16,
          "text-allow-overlap": false,
          "text-padding": 4,
        },
        paint: {
          "text-color": "#183128",
          "text-halo-color": "rgba(255, 253, 248, 0.92)",
          "text-halo-width": 1.5,
        },
      }, beforeId)

      this.applyStateFilter()
      this.applyLayerPreferences()
    } catch (error) {
      if (error.name !== "AbortError") console.warn("State markings unavailable", error)
    }
  },

  applyStateFilter() {
    if (!this.map?.getLayer("brazil-states-selected")) return

    const state = this.filters?.state?.trim().toUpperCase()
    const selectedState = /^[A-Z]{2}$/.test(state || "") ? state : "__none__"
    const filter = ["==", ["get", "state_code"], selectedState]
    this.map.setFilter("brazil-states-selected", filter)
    this.map.setFilter("brazil-states-selected-boundary", filter)
  },

  setupLayerControl() {
    this.layerControl = this.el.parentElement?.querySelector("[data-map-layers]")
    if (!this.layerControl) return

    const toggle = this.layerControl.querySelector("[data-map-layers-toggle]")
    const panel = this.layerControl.querySelector("[data-map-layers-panel]")

    this.onLayerControlClick = event => {
      const basemapButton = event.target.closest("[data-basemap]")
      if (basemapButton) this.setBasemap(basemapButton.dataset.basemap)

      if (event.target.closest("[data-map-layers-toggle]")) {
        const opening = panel.hidden
        panel.hidden = !opening
        toggle.setAttribute("aria-expanded", String(opening))
      }
    }

    this.onLayerControlInput = event => {
      const layer = event.target.dataset.layerToggle
      if (layer === "mining" || layer === "states") {
        this.layerPreferences[layer] = event.target.checked
        this.applyLayerPreferences()
        this.saveLayerPreferences()
      }

      if (event.target.matches("[data-mining-opacity]")) {
        this.layerPreferences.miningOpacity = Number(event.target.value) / 100
        this.applyMiningOpacity()
        this.updateLayerControl()
        this.saveLayerPreferences()
      }
    }

    this.onLayerDocumentPointerDown = event => {
      if (!panel.hidden && !this.layerControl.contains(event.target)) {
        panel.hidden = true
        toggle.setAttribute("aria-expanded", "false")
      }
    }

    this.onLayerDocumentKeyDown = event => {
      if (event.key === "Escape" && !panel.hidden) {
        panel.hidden = true
        toggle.setAttribute("aria-expanded", "false")
        toggle.focus()
      }
    }

    this.layerControl.addEventListener("click", this.onLayerControlClick)
    this.layerControl.addEventListener("input", this.onLayerControlInput)
    document.addEventListener("pointerdown", this.onLayerDocumentPointerDown)
    document.addEventListener("keydown", this.onLayerDocumentKeyDown)
    this.updateLayerControl()
  },

  setBasemap(basemap) {
    if (basemap === "satellite" && !this.satelliteTilejsonUrl) return

    if (basemap === "satellite") {
      this.ensureSatelliteLayer()
      this.setLayerStatus("Carregando imagem…")
    }

    this.layerPreferences.basemap = basemap
    this.applyBasemap()
    this.updateLayerControl()
    this.saveLayerPreferences()
  },

  ensureSatelliteLayer() {
    if (!this.map || this.map.getSource("satellite-basemap")) return

    this.map.addSource("satellite-basemap", {
      type: "raster",
      url: this.satelliteTilejsonUrl,
      tileSize: 256,
    })

    const beforeId = stateLayerIds.find(id => this.map.getLayer(id)) ||
      (this.map.getLayer("mining-clusters") ? "mining-clusters" : undefined)

    this.map.addLayer({
      id: "satellite-basemap",
      type: "raster",
      source: "satellite-basemap",
      paint: {"raster-fade-duration": 220},
    }, beforeId)
  },

  handleSatelliteError() {
    if (this.layerPreferences.basemap !== "satellite") return

    this.layerPreferences.basemap = "street"
    this.applyBasemap()
    if (this.map.getLayer("satellite-basemap")) this.map.removeLayer("satellite-basemap")
    if (this.map.getSource("satellite-basemap")) this.map.removeSource("satellite-basemap")
    this.updateLayerControl()
    this.saveLayerPreferences()
    this.setLayerStatus("Satélite indisponível")
  },

  applyLayerPreferences() {
    if (!this.map) return

    this.applyBasemap()
    this.setLayersVisibility(miningLayerIds, this.layerPreferences.mining)
    this.setLayersVisibility(stateLayerIds, this.layerPreferences.states)
    this.applyMiningOpacity()
    this.updateLayerControl()
  },

  applyBasemap() {
    if (!this.map) return
    if (this.layerPreferences.basemap === "satellite") this.ensureSatelliteLayer()

    if (this.map.getLayer("satellite-basemap")) {
      this.map.setLayoutProperty(
        "satellite-basemap",
        "visibility",
        this.layerPreferences.basemap === "satellite" ? "visible" : "none",
      )
    }
  },

  setLayersVisibility(layerIds, visible) {
    layerIds.forEach(id => {
      if (this.map.getLayer(id)) {
        this.map.setLayoutProperty(id, "visibility", visible ? "visible" : "none")
      }
    })
  },

  applyMiningOpacity() {
    if (!this.map) return
    const opacity = this.layerPreferences.miningOpacity

    if (this.map.getLayer("mining-clusters")) {
      this.map.setPaintProperty("mining-clusters", "circle-opacity", 0.8 * opacity)
    }

    if (this.map.getLayer("mining-polygons")) {
      this.map.setPaintProperty("mining-polygons", "fill-opacity", [
        "interpolate",
        ["linear"],
        ["zoom"],
        7,
        0.45 * opacity,
        12,
        0.68 * opacity,
      ])
    }
  },

  updateLayerControl() {
    if (!this.layerControl) return

    this.layerControl.querySelectorAll("[data-basemap]").forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.basemap === this.layerPreferences.basemap))
    })

    const miningToggle = this.layerControl.querySelector("[data-layer-toggle='mining']")
    const statesToggle = this.layerControl.querySelector("[data-layer-toggle='states']")
    const opacityInput = this.layerControl.querySelector("[data-mining-opacity]")
    const opacityOutput = this.layerControl.querySelector("[data-mining-opacity-output]")
    const opacityControl = this.layerControl.querySelector("[data-mining-opacity-control]")

    if (miningToggle) miningToggle.checked = this.layerPreferences.mining
    if (statesToggle) statesToggle.checked = this.layerPreferences.states
    if (opacityInput) {
      opacityInput.value = Math.round(this.layerPreferences.miningOpacity * 100)
      opacityInput.disabled = !this.layerPreferences.mining
    }
    if (opacityOutput) opacityOutput.value = `${Math.round(this.layerPreferences.miningOpacity * 100)}%`
    opacityControl?.classList.toggle("opacity-45", !this.layerPreferences.mining)
  },

  setLayerStatus(message) {
    const status = this.layerControl?.querySelector("[data-map-layer-status]")
    if (status) status.textContent = message
  },

  saveLayerPreferences() {
    try {
      window.localStorage.setItem(layerPreferenceKey, JSON.stringify(this.layerPreferences))
    } catch (_error) {
      // Storage can be unavailable in privacy modes; the map remains fully usable.
    }
  },

  destroyed() {
    this.abortController?.abort()
    this.layerControl?.removeEventListener("click", this.onLayerControlClick)
    this.layerControl?.removeEventListener("input", this.onLayerControlInput)
    document.removeEventListener("pointerdown", this.onLayerDocumentPointerDown)
    document.removeEventListener("keydown", this.onLayerDocumentKeyDown)
    this.map?.remove()
  },
}

export default MiningMap
