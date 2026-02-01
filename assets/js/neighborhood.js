import * as THREE from "three";

/**
 * Neighborhood Scene
 *
 * Isometric view of a seeded neighborhood in Vacaville, CA.
 * Origin: 38.3566°N, 121.9877°W
 *
 * Coordinate system:
 * - X axis: East-West (positive = East)
 * - Y axis: Altitude (positive = up)
 * - Z axis: North-South (positive = North)
 * - 1 unit = 1 meter
 *
 * Controls:
 * - WASD / Arrow keys: Move the viewer
 * - Click on ground: Move to that location
 * - Click on user: Select/interact with user
 *
 * User indicators:
 * - Verification halo: glowing ring for verified users (DID and/or feed)
 * - Seller badge: floating icon above users with items for sale
 * - Connection visibility: connected users are solid, others translucent
 * - Viewer highlight: pulsing outline around your avatar
 */

export function renderNeighborhood(containerId, options = {}) {
  const container = document.getElementById(containerId);
  if (!container) return null;

  // Configuration with defaults
  const config = {
    users: options.users || [],
    currentUserId: options.currentUserId || null,
    connections: options.connections || [],
    onUserClick: options.onUserClick || null,
    onMove: options.onMove || null,        // Send movement direction to server
    onMoveTo: options.onMoveTo || null,    // Send click-to-move target to server
    ...options
  };

  // World origin (Vacaville, CA)
  const origin = { lat: 38.3566, long: -121.9877 };

  // Scene setup
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x1a1a2e);

  const width = container.clientWidth;
  const height = container.clientHeight;

  // Isometric camera setup using OrthographicCamera
  const aspect = width / height;
  const viewSize = 80; // meters visible
  const camera = new THREE.OrthographicCamera(
    -viewSize * aspect / 2,
    viewSize * aspect / 2,
    viewSize / 2,
    -viewSize / 2,
    0.1,
    1000
  );

  // Classic isometric angle
  const camDistance = 100;
  camera.position.set(camDistance, camDistance, camDistance);
  camera.lookAt(0, 0, 0);

  // Renderer
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(width, height);
  renderer.setPixelRatio(window.devicePixelRatio);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  container.appendChild(renderer.domElement);

  // Canvas styling
  renderer.domElement.style.outline = "none";
  renderer.domElement.style.cursor = "pointer";

  // Lighting
  const ambientLight = new THREE.AmbientLight(0x404060, 0.6);
  scene.add(ambientLight);

  const sunLight = new THREE.DirectionalLight(0xffffee, 1.0);
  sunLight.position.set(50, 100, 50);
  sunLight.castShadow = true;
  sunLight.shadow.mapSize.width = 2048;
  sunLight.shadow.mapSize.height = 2048;
  sunLight.shadow.camera.near = 10;
  sunLight.shadow.camera.far = 300;
  sunLight.shadow.camera.left = -100;
  sunLight.shadow.camera.right = 100;
  sunLight.shadow.camera.top = 100;
  sunLight.shadow.camera.bottom = -100;
  scene.add(sunLight);

  // Ground plane
  const groundGeometry = new THREE.PlaneGeometry(200, 200);
  let groundMaterial = new THREE.MeshStandardMaterial({
    color: 0x3d5c3d,
    roughness: 0.9
  });
  const ground = new THREE.Mesh(groundGeometry, groundMaterial);
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  ground.userData.isGround = true;
  scene.add(ground);

  // Group for location-specific scenery (streets, buildings)
  const sceneryGroup = new THREE.Group();
  scene.add(sceneryGroup);

  // Seeded random for consistent generation
  function seededRandom(seed) {
    const x = Math.sin(seed) * 10000;
    return x - Math.floor(x);
  }

  let seedCounter = 12345;
  function random() {
    seedCounter++;
    return seededRandom(seedCounter);
  }

  // Location-specific themes
  const locationThemes = {
    "vacaville-ca": {
      ground: 0x3d5c3d,        // Green grass (farm)
      street: 0x555555,        // Light gray roads
      buildings: [0x8b7355, 0xa0936e, 0x92400e, 0x78350f, 0x654321], // Browns (barns)
      buildingHeight: { min: 3, max: 6 },  // Low buildings
      seed: 1000
    },
    "san-francisco-ca": {
      ground: 0x4a4a4a,        // Gray/concrete
      street: 0x333333,        // Dark roads
      buildings: [0x64748b, 0x475569, 0x334155, 0x1e293b, 0x94a3b8], // Grays/blues (skyscrapers)
      buildingHeight: { min: 8, max: 20 }, // Tall buildings
      seed: 2000
    },
    "vallejo-ca": {
      ground: 0x3d4c5c,        // Blue-gray (maritime)
      street: 0x444444,
      buildings: [0x0284c7, 0x0369a1, 0x075985, 0x164e63, 0x155e75], // Blues (waterfront)
      buildingHeight: { min: 4, max: 10 },
      seed: 3000
    },
    "oakland-ca": {
      ground: 0x4a4a3d,        // Olive/industrial
      street: 0x3a3a3a,
      buildings: [0xea580c, 0xc2410c, 0x9a3412, 0x78350f, 0xfbbf24], // Oranges/industrial
      buildingHeight: { min: 5, max: 15 },
      seed: 4000
    },
    "sacramento-ca": {
      ground: 0x4a5c3d,        // Green with yellow tint
      street: 0x4a4a4a,
      buildings: [0xf5f5f4, 0xe7e5e4, 0xd6d3d1, 0xfbbf24, 0xf59e0b], // Whites/golds (government)
      buildingHeight: { min: 4, max: 12 },
      seed: 5000
    }
  };

  // Street creation
  function createStreet(x, z, streetWidth, length, vertical, color) {
    const streetGeometry = new THREE.PlaneGeometry(
      vertical ? streetWidth : length,
      vertical ? length : streetWidth
    );
    const streetMaterial = new THREE.MeshStandardMaterial({
      color: color,
      roughness: 0.8
    });
    const street = new THREE.Mesh(streetGeometry, streetMaterial);
    street.rotation.x = -Math.PI / 2;
    street.position.set(x, 0.01, z);
    street.receiveShadow = true;
    return street;
  }

  // Building creation
  function createBuilding(x, z, w, d, h, color) {
    const geometry = new THREE.BoxGeometry(w, h, d);
    const material = new THREE.MeshStandardMaterial({
      color: color,
      roughness: 0.7
    });
    const building = new THREE.Mesh(geometry, material);
    building.position.set(x, h / 2, z);
    building.castShadow = true;
    building.receiveShadow = true;
    return building;
  }

  // Generate scenery for a location
  function generateScenery(slug) {
    // Clear existing scenery
    while (sceneryGroup.children.length > 0) {
      sceneryGroup.remove(sceneryGroup.children[0]);
    }

    const theme = locationThemes[slug] || locationThemes["vacaville-ca"];

    // Update ground color
    ground.material.color.setHex(theme.ground);

    // Street dimensions
    const streetWidth = 8;
    const blockSize = 40;

    // Create streets
    sceneryGroup.add(createStreet(0, -blockSize / 2, streetWidth, 180, false, theme.street));
    sceneryGroup.add(createStreet(0, blockSize / 2, streetWidth, 180, false, theme.street));
    sceneryGroup.add(createStreet(-blockSize, 0, streetWidth, 100, true, theme.street));
    sceneryGroup.add(createStreet(0, 0, streetWidth, 100, true, theme.street));
    sceneryGroup.add(createStreet(blockSize, 0, streetWidth, 100, true, theme.street));

    // Seed buildings in blocks
    function seedBlock(centerX, centerZ, blockSeed) {
      seedCounter = blockSeed;
      const buildingCount = 3 + Math.floor(random() * 4);

      for (let i = 0; i < buildingCount; i++) {
        const bx = centerX + (random() - 0.5) * 28;
        const bz = centerZ + (random() - 0.5) * 28;
        const bw = 5 + random() * 8;
        const bd = 5 + random() * 8;
        const bh = theme.buildingHeight.min + random() * (theme.buildingHeight.max - theme.buildingHeight.min);
        const color = theme.buildings[Math.floor(random() * theme.buildings.length)];

        sceneryGroup.add(createBuilding(bx, bz, bw, bd, bh, color));
      }
    }

    // Create 4 blocks with location-specific seed
    seedBlock(-blockSize / 2, -blockSize, theme.seed + 1);
    seedBlock(blockSize / 2, -blockSize, theme.seed + 2);
    seedBlock(-blockSize / 2, blockSize, theme.seed + 3);
    seedBlock(blockSize / 2, blockSize, theme.seed + 4);

    console.log("[neighborhood] Generated scenery for", slug);
  }

  // Generate initial scenery - use provided location or default to Vacaville
  const initialSlug = config.initialLocation?.slug || "vacaville-ca";
  generateScenery(initialSlug);

  // Set initial sky color based on location
  const initialSkyColor = {
    "vacaville-ca": 0x1a1a2e,
    "san-francisco-ca": 0x2e1a1a,
    "vallejo-ca": 0x1a2e2e,
    "oakland-ca": 0x2e2e1a,
    "sacramento-ca": 0x2e1a2e
  }[initialSlug] || 0x1a1a2e;
  scene.background = new THREE.Color(initialSkyColor);

  // Set initial origin if provided
  if (config.initialLocation?.center_lat && config.initialLocation?.center_long) {
    origin.lat = config.initialLocation.center_lat;
    origin.long = config.initialLocation.center_long;
  }

  // Default users for development/demo
  const defaultUsers = [
    {
      id: "viewer",
      name: "You",
      website: "https://yoursite.example",
      position: { x: 0, z: 0 },
      color: "#4a90d9",
      connections: ["alice"],
      isViewer: true,
      verificationLevel: 0,
      hasProducts: false
    },
    {
      id: "alice",
      name: "Alice",
      website: "https://alice.example.com",
      position: { x: 8, z: 5 },
      color: "#d94a8a",
      connections: ["viewer"],
      verificationLevel: 2,
      hasProducts: true
    },
    {
      id: "bob",
      name: "Bob",
      website: "https://bob.example.com",
      position: { x: 15, z: -8 },
      color: "#8ad94a",
      connections: [],
      verificationLevel: 1,
      hasProducts: false
    },
    {
      id: "carol",
      name: "Carol",
      website: "https://carol.example.com",
      position: { x: -12, z: 10 },
      color: "#d9a84a",
      connections: [],
      verificationLevel: 0,
      hasProducts: false
    }
  ];

  const users = config.users.length > 0 ? config.users : defaultUsers;
  const viewer = users.find(u => u.isViewer) || users[0];

  // Boundary lines group
  const boundaryGroup = new THREE.Group();
  scene.add(boundaryGroup);

  // World objects group
  const worldObjectsGroup = new THREE.Group();
  scene.add(worldObjectsGroup);
  const worldObjectMeshes = new Map(); // id -> mesh

  // Place mode state
  let placeModeEnabled = false;

  // Determine visibility/opacity based on connections
  function getOpacity(viewerUser, subject) {
    if (!viewerUser) return 0.6;
    if (subject.isViewer) return 1.0;
    if (subject.id === config.currentUserId) return 1.0;
    if (viewerUser.connections && viewerUser.connections.includes(subject.id)) return 1.0;
    if (config.connections.includes(subject.id)) return 1.0;
    return 0.4; // Public but not connected
  }

  // Color conversion helper
  function parseColor(color) {
    if (typeof color === "number") return color;
    if (typeof color === "string" && color.startsWith("#")) {
      return parseInt(color.slice(1), 16);
    }
    return 0x4a90d9; // default blue
  }

  // Create verification halo (glowing ring)
  function createVerificationHalo(verificationLevel) {
    if (verificationLevel === 0) return null;

    const group = new THREE.Group();

    // Ring geometry
    const innerRadius = 0.5;
    const outerRadius = 0.65;
    const ringGeometry = new THREE.RingGeometry(innerRadius, outerRadius, 32);

    // Color based on verification level
    const haloColor = verificationLevel === 2 ? 0x00ff88 : 0x00aaff;

    const ringMaterial = new THREE.MeshBasicMaterial({
      color: haloColor,
      transparent: true,
      opacity: 0.7,
      side: THREE.DoubleSide
    });

    const ring = new THREE.Mesh(ringGeometry, ringMaterial);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 2.3;
    group.add(ring);

    // Add second ring for level 2
    if (verificationLevel === 2) {
      const outerRingGeometry = new THREE.RingGeometry(0.7, 0.8, 32);
      const outerRing = new THREE.Mesh(outerRingGeometry, ringMaterial.clone());
      outerRing.rotation.x = -Math.PI / 2;
      outerRing.position.y = 2.3;
      group.add(outerRing);
    }

    return group;
  }

  // Create seller badge (floating icon)
  function createSellerBadge() {
    const group = new THREE.Group();

    // Simple diamond/tag shape
    const badgeGeometry = new THREE.OctahedronGeometry(0.2, 0);
    const badgeMaterial = new THREE.MeshBasicMaterial({
      color: 0xffd700, // Gold
      transparent: true,
      opacity: 0.9
    });

    const badge = new THREE.Mesh(badgeGeometry, badgeMaterial);
    badge.position.y = 2.8;
    badge.rotation.x = Math.PI / 4;
    group.add(badge);

    return group;
  }

  // Create viewer highlight (pulsing circle under feet)
  function createViewerHighlight() {
    const group = new THREE.Group();

    // Outer ring
    const ringGeometry = new THREE.RingGeometry(0.6, 0.8, 32);
    const ringMaterial = new THREE.MeshBasicMaterial({
      color: 0x00ffff,
      transparent: true,
      opacity: 0.8,
      side: THREE.DoubleSide
    });

    const ring = new THREE.Mesh(ringGeometry, ringMaterial);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.02;
    group.add(ring);

    // Inner glow
    const glowGeometry = new THREE.CircleGeometry(0.5, 32);
    const glowMaterial = new THREE.MeshBasicMaterial({
      color: 0x00ffff,
      transparent: true,
      opacity: 0.3,
      side: THREE.DoubleSide
    });

    const glow = new THREE.Mesh(glowGeometry, glowMaterial);
    glow.rotation.x = -Math.PI / 2;
    glow.position.y = 0.01;
    group.add(glow);

    // Direction indicator (arrow pointing forward)
    const arrowShape = new THREE.Shape();
    arrowShape.moveTo(0, 0.4);
    arrowShape.lineTo(-0.15, 0.15);
    arrowShape.lineTo(0.15, 0.15);
    arrowShape.closePath();

    const arrowGeometry = new THREE.ShapeGeometry(arrowShape);
    const arrowMaterial = new THREE.MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
      opacity: 0.9,
      side: THREE.DoubleSide
    });

    const arrow = new THREE.Mesh(arrowGeometry, arrowMaterial);
    arrow.rotation.x = -Math.PI / 2;
    arrow.position.y = 0.03;
    arrow.position.z = -0.3;
    group.add(arrow);

    return group;
  }

  // Create conversation indicator (speech bubble)
  function createConversationIndicator() {
    const group = new THREE.Group();

    // Speech bubble body (rounded rectangle approximated with sphere + cylinder)
    const bubbleGeometry = new THREE.SphereGeometry(0.25, 16, 16);
    const bubbleMaterial = new THREE.MeshBasicMaterial({
      color: 0xffffff,
      transparent: true,
      opacity: 0.9
    });

    const bubble = new THREE.Mesh(bubbleGeometry, bubbleMaterial);
    bubble.scale.set(1.2, 0.8, 0.4);
    bubble.position.set(0.5, 2.5, 0);
    group.add(bubble);

    // Tail pointing to head
    const tailGeometry = new THREE.ConeGeometry(0.08, 0.2, 8);
    const tail = new THREE.Mesh(tailGeometry, bubbleMaterial);
    tail.position.set(0.3, 2.3, 0);
    tail.rotation.z = Math.PI / 4;
    group.add(tail);

    // Typing dots (three small spheres)
    const dotGeometry = new THREE.SphereGeometry(0.04, 8, 8);
    const dotMaterial = new THREE.MeshBasicMaterial({ color: 0x888888 });

    for (let i = 0; i < 3; i++) {
      const dot = new THREE.Mesh(dotGeometry, dotMaterial.clone());
      dot.position.set(0.35 + i * 0.1, 2.5, 0.05);
      dot.userData.dotIndex = i;
      group.add(dot);
    }

    group.visible = false;
    group.userData.isTyping = false;
    group.userData.inConversation = false;

    return group;
  }

  // Create message notification indicator (exclamation in circle, pulsing)
  function createMessageIndicator() {
    const group = new THREE.Group();

    // Circle background
    const circleGeometry = new THREE.CircleGeometry(0.2, 16);
    const circleMaterial = new THREE.MeshBasicMaterial({
      color: 0xff4444,
      transparent: true,
      opacity: 0.9
    });
    const circle = new THREE.Mesh(circleGeometry, circleMaterial);
    circle.position.set(-0.5, 2.5, 0);
    group.add(circle);

    // Exclamation mark (simple line + dot)
    const exclamationGeometry = new THREE.BoxGeometry(0.04, 0.15, 0.04);
    const exclamationMaterial = new THREE.MeshBasicMaterial({ color: 0xffffff });
    const exclamationLine = new THREE.Mesh(exclamationGeometry, exclamationMaterial);
    exclamationLine.position.set(-0.5, 2.53, 0.01);
    group.add(exclamationLine);

    const dotGeometry = new THREE.CircleGeometry(0.03, 8);
    const dot = new THREE.Mesh(dotGeometry, exclamationMaterial);
    dot.position.set(-0.5, 2.4, 0.01);
    group.add(dot);

    group.visible = false;
    group.userData.hasMessage = false;
    group.userData.pulsePhase = 0;

    return group;
  }

  // Create movement target indicator
  function createTargetIndicator() {
    const group = new THREE.Group();

    const ringGeometry = new THREE.RingGeometry(0.3, 0.4, 32);
    const ringMaterial = new THREE.MeshBasicMaterial({
      color: 0xffff00,
      transparent: true,
      opacity: 0.8,
      side: THREE.DoubleSide
    });

    const ring = new THREE.Mesh(ringGeometry, ringMaterial);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.02;
    group.add(ring);

    group.visible = false;
    return group;
  }

  // Create boundary lines from GeoJSON
  function createBoundaryLines(geojson) {
    // Clear existing boundaries
    while (boundaryGroup.children.length > 0) {
      boundaryGroup.remove(boundaryGroup.children[0]);
    }

    if (!geojson) return;

    let data;
    try {
      data = typeof geojson === "string" ? JSON.parse(geojson) : geojson;
    } catch (e) {
      console.error("Failed to parse boundary GeoJSON:", e);
      return;
    }

    const features = data.features || [];
    const lineMaterial = new THREE.LineBasicMaterial({
      color: 0x9966ff,
      linewidth: 2,
      transparent: true,
      opacity: 0.7
    });

    features.forEach(feature => {
      const geometry = feature.geometry;
      if (!geometry) return;

      const coords = geometry.type === "Polygon"
        ? geometry.coordinates[0]
        : geometry.type === "LineString"
          ? geometry.coordinates
          : [];

      if (coords.length < 2) return;

      // Convert lat/long to local coordinates (simplified - assumes small area)
      // Center of our coordinate system is origin (0, 0)
      // For now, scale by a factor to make boundaries visible
      const scale = 1000; // meters per degree (approximate)
      const centerLat = origin.lat;
      const centerLong = origin.long;

      const points = coords.map(([lon, lat]) => {
        const x = (lon - centerLong) * scale;
        const z = -(lat - centerLat) * scale; // Negative because Z is south
        return new THREE.Vector3(x, 0.1, z);
      });

      const lineGeometry = new THREE.BufferGeometry().setFromPoints(points);
      const line = new THREE.Line(lineGeometry, lineMaterial);
      boundaryGroup.add(line);
    });
  }

  // Create a world object mesh
  function createWorldObject(obj) {
    const group = new THREE.Group();
    const color = parseColor(obj.color || "#4a90d9");

    const material = new THREE.MeshStandardMaterial({
      color: color,
      roughness: 0.5,
      metalness: 0.2
    });

    let mesh;
    switch (obj.object_type) {
      case "pin":
        // Pin: tall thin cylinder with sphere on top
        const pinBody = new THREE.Mesh(
          new THREE.CylinderGeometry(0.05, 0.05, 1.5, 8),
          material
        );
        pinBody.position.y = 0.75;
        pinBody.castShadow = true;
        group.add(pinBody);

        const pinHead = new THREE.Mesh(
          new THREE.SphereGeometry(0.2, 16, 16),
          material
        );
        pinHead.position.y = 1.6;
        pinHead.castShadow = true;
        group.add(pinHead);
        break;

      case "cube":
        mesh = new THREE.Mesh(
          new THREE.BoxGeometry(0.8, 0.8, 0.8),
          material
        );
        mesh.position.y = 0.4;
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        group.add(mesh);
        break;

      case "model":
        // Placeholder for custom models - use a cone for now
        mesh = new THREE.Mesh(
          new THREE.ConeGeometry(0.4, 1.2, 8),
          material
        );
        mesh.position.y = 0.6;
        mesh.castShadow = true;
        group.add(mesh);
        break;

      default:
        // Default sphere
        mesh = new THREE.Mesh(
          new THREE.SphereGeometry(0.3, 16, 16),
          material
        );
        mesh.position.y = 0.3;
        mesh.castShadow = true;
        group.add(mesh);
    }

    // Add label if present
    if (obj.label) {
      // Labels would need a sprite or CSS2DObject - skipping for now
    }

    group.position.set(obj.position_x, obj.position_y || 0, obj.position_z);
    group.userData = { object: obj };

    return group;
  }

  // Add a world object to the scene
  function addWorldObject(obj) {
    const mesh = createWorldObject(obj);
    worldObjectsGroup.add(mesh);
    worldObjectMeshes.set(obj.id, mesh);
  }

  // Remove a world object from the scene
  function removeWorldObject(id) {
    const mesh = worldObjectMeshes.get(id);
    if (mesh) {
      worldObjectsGroup.remove(mesh);
      worldObjectMeshes.delete(id);
    }
  }

  // Update a world object
  function updateWorldObject(obj) {
    removeWorldObject(obj.parent_id || obj.id);
    addWorldObject(obj);
  }

  // Location-based sky colors
  const locationColors = {
    "vacaville-ca": 0x1a1a2e,      // Dark blue (default)
    "san-francisco-ca": 0x2e1a1a,  // Dark red
    "vallejo-ca": 0x1a2e2e,        // Dark cyan
    "oakland-ca": 0x2e2e1a,        // Dark yellow
    "sacramento-ca": 0x2e1a2e      // Dark purple
  };

  // Update location (travel to new location)
  function updateLocation(locationData) {
    console.log("[neighborhood] updateLocation called:", locationData);

    // Clear all world objects from old location
    clearAllWorldObjects();

    // Change sky color based on location
    const skyColor = locationColors[locationData.slug] || 0x1a1a2e;
    scene.background = new THREE.Color(skyColor);

    // Regenerate scenery (streets, buildings) for new location
    generateScenery(locationData.slug);

    // Update boundary lines
    if (locationData.bounds_geojson) {
      createBoundaryLines(locationData.bounds_geojson);
    } else {
      // Clear boundaries if none
      while (boundaryGroup.children.length > 0) {
        boundaryGroup.remove(boundaryGroup.children[0]);
      }
    }

    // Update origin for coordinate conversion
    if (locationData.center_lat && locationData.center_long) {
      origin.lat = locationData.center_lat;
      origin.long = locationData.center_long;
    }

    // Reset camera to center on origin (viewer will be moved by position update)
    camera.position.set(camDistance, camDistance, camDistance);
    camera.lookAt(0, 0, 0);
    cameraPanTarget = null;

    // Center on viewer figure if it exists
    if (viewerFigure) {
      const vx = viewerFigure.position.x;
      const vz = viewerFigure.position.z;
      camera.position.set(vx + camDistance, camDistance, vz + camDistance);
      camera.lookAt(vx, 0, vz);
    }
  }

  // Clear all world objects
  function clearAllWorldObjects() {
    worldObjectMeshes.forEach((mesh, id) => {
      worldObjectsGroup.remove(mesh);
    });
    worldObjectMeshes.clear();
  }

  // Set place mode
  function setPlaceMode(enabled) {
    placeModeEnabled = enabled;
    renderer.domElement.style.cursor = enabled ? "crosshair" : "pointer";
  }

  // Create figure (simple human shape)
  function createFigure(user, opacity) {
    const group = new THREE.Group();
    const color = parseColor(user.color);

    const bodyMaterial = new THREE.MeshStandardMaterial({
      color: color,
      transparent: opacity < 1,
      opacity: opacity,
      roughness: 0.6
    });

    // Body (capsule-like: cylinder + spheres)
    const bodyGeometry = new THREE.CylinderGeometry(0.4, 0.35, 1.2, 16);
    const body = new THREE.Mesh(bodyGeometry, bodyMaterial);
    body.position.y = 1.0;
    body.castShadow = true;
    group.add(body);

    // Head
    const headGeometry = new THREE.SphereGeometry(0.3, 16, 16);
    const head = new THREE.Mesh(headGeometry, bodyMaterial);
    head.position.y = 1.9;
    head.castShadow = true;
    group.add(head);

    // Legs (two cylinders)
    const legGeometry = new THREE.CylinderGeometry(0.12, 0.12, 0.7, 8);
    const leftLeg = new THREE.Mesh(legGeometry, bodyMaterial);
    leftLeg.position.set(-0.15, 0.35, 0);
    leftLeg.castShadow = true;
    group.add(leftLeg);

    const rightLeg = new THREE.Mesh(legGeometry, bodyMaterial);
    rightLeg.position.set(0.15, 0.35, 0);
    rightLeg.castShadow = true;
    group.add(rightLeg);

    // Add verification halo if verified
    const verificationLevel = user.verificationLevel || 0;
    const halo = createVerificationHalo(verificationLevel);
    if (halo) {
      group.add(halo);
      group.userData.halo = halo;
    }

    // Add seller badge if has products
    if (user.hasProducts) {
      const badge = createSellerBadge();
      group.add(badge);
      group.userData.sellerBadge = badge;
    }

    // Add viewer highlight if this is the viewer
    if (user.isViewer) {
      const highlight = createViewerHighlight();
      group.add(highlight);
      group.userData.viewerHighlight = highlight;
    }

    // Add conversation indicator (hidden by default)
    const conversationIndicator = createConversationIndicator();
    group.add(conversationIndicator);
    group.userData.conversationIndicator = conversationIndicator;

    // Add message notification indicator (hidden by default)
    const messageIndicator = createMessageIndicator();
    group.add(messageIndicator);
    group.userData.messageIndicator = messageIndicator;

    // Position
    const pos = user.position || { x: random() * 20 - 10, z: random() * 20 - 10 };
    group.position.set(pos.x, 0, pos.z);
    group.userData = {
      ...group.userData,
      user: user,
      opacity: opacity,
      basePosition: { x: pos.x, z: pos.z },
      isViewer: user.isViewer || false
    };

    return group;
  }

  // Create all figures
  const figures = [];
  let viewerFigure = null;

  users.forEach((user) => {
    const opacity = getOpacity(viewer, user);
    const figure = createFigure(user, opacity);
    figures.push(figure);
    scene.add(figure);

    if (user.isViewer) {
      viewerFigure = figure;
    }
  });

  // Create target indicator
  const targetIndicator = createTargetIndicator();
  scene.add(targetIndicator);

  // Movement state - now server-authoritative, client just sends intents
  const movement = {
    keys: {
      up: false,
      down: false,
      left: false,
      right: false
    }
  };

  // Track entity positions for interpolation
  const entityPositions = new Map();

  // Movement intent throttling
  let lastMoveIntent = 0;
  const MOVE_INTENT_INTERVAL = 50; // ms between move intents

  // Update info panel
  function updateInfoPanel() {
    const figureListEl = document.getElementById("figure-list");
    if (!figureListEl) return;

    figureListEl.innerHTML = "";
    users.forEach(user => {
      const opacity = getOpacity(viewer, user);
      const connected = opacity === 1.0;
      const colorHex = typeof user.color === "string"
        ? user.color
        : "#" + parseColor(user.color).toString(16).padStart(6, "0");

      const div = document.createElement("div");
      div.style.cssText = `
        padding: 6px 0;
        border-bottom: 1px solid #333;
        opacity: ${opacity};
        cursor: pointer;
      `;

      let badges = "";
      if (user.verificationLevel === 2) {
        badges += '<span style="color: #0f8; font-size: 10px; margin-left: 4px;">✓✓</span>';
      } else if (user.verificationLevel === 1) {
        badges += '<span style="color: #0af; font-size: 10px; margin-left: 4px;">✓</span>';
      }
      if (user.hasProducts) {
        badges += '<span style="color: #fd0; font-size: 10px; margin-left: 4px;">💰</span>';
      }

      div.innerHTML = `
        <div style="display: flex; align-items: center; gap: 8px;">
          <div style="width: 10px; height: 10px; border-radius: 50%; background: ${colorHex};"></div>
          <span>${user.name || user.display_name || "Anonymous"}</span>
          ${badges}
          ${connected && !user.isViewer ? '<span style="color: #4a4; font-size: 10px;">connected</span>' : ''}
          ${user.isViewer ? '<span style="color: #0ff; font-size: 10px;">you</span>' : ''}
        </div>
        <div style="font-size: 10px; color: #666; margin-top: 2px; margin-left: 18px;">
          ${user.website || user.did || ""}
        </div>
      `;

      // Click handler
      if (config.onUserClick && !user.isViewer) {
        div.onclick = () => config.onUserClick(user);
      }

      figureListEl.appendChild(div);
    });

    // Add controls hint
    const hint = document.createElement("div");
    hint.style.cssText = "margin-top: 8px; padding-top: 8px; border-top: 1px solid #444; color: #666; font-size: 9px;";
    hint.innerHTML = "WASD/Arrows: Move • Click: Go to";
    figureListEl.appendChild(hint);
  }

  updateInfoPanel();

  // Animation state
  let time = 0;
  let animationId = null;
  let lastTime = performance.now();

  // Camera panning state
  let cameraPanTarget = null;
  const cameraOffset = { x: camDistance, y: camDistance, z: camDistance };

  function animate() {
    animationId = requestAnimationFrame(animate);

    const now = performance.now();
    const delta = (now - lastTime) / 1000; // seconds
    lastTime = now;

    time += delta;

    // Handle camera panning
    if (cameraPanTarget) {
      const targetCamX = cameraPanTarget.x + cameraOffset.x;
      const targetCamZ = cameraPanTarget.z + cameraOffset.z;

      const panSpeed = 5 * delta;
      const dx = targetCamX - camera.position.x;
      const dz = targetCamZ - camera.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);

      if (dist > 0.5) {
        const ratio = Math.min(panSpeed / dist, 1);
        camera.position.x += dx * ratio;
        camera.position.z += dz * ratio;
        camera.lookAt(cameraPanTarget.x, 0, cameraPanTarget.z);
      } else {
        // Arrived at target
        cameraPanTarget = null;
      }
    }

    // Send movement intents to server (throttled)
    if (now - lastMoveIntent > MOVE_INTENT_INTERVAL && config.onMove) {
      if (movement.keys.up) {
        config.onMove("up");
        lastMoveIntent = now;
      } else if (movement.keys.down) {
        config.onMove("down");
        lastMoveIntent = now;
      } else if (movement.keys.left) {
        config.onMove("left");
        lastMoveIntent = now;
      } else if (movement.keys.right) {
        config.onMove("right");
        lastMoveIntent = now;
      }
    }

    // Interpolate all figures to their server positions
    figures.forEach((figure) => {
      const userId = figure.userData.user?.id;
      const targetPos = entityPositions.get(userId);

      if (targetPos) {
        const lerpSpeed = 10 * delta; // Smooth follow
        const dx = targetPos.x - figure.position.x;
        const dz = targetPos.z - figure.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);

        if (dist > 0.05) {
          // Move towards target
          const ratio = Math.min(lerpSpeed / dist, 1);
          figure.position.x += dx * ratio;
          figure.position.z += dz * ratio;

          // Face movement direction
          figure.rotation.y = Math.atan2(dx, dz);

          // Walking animation
          figure.position.y = Math.abs(Math.sin(time * 8)) * 0.08;
        } else {
          figure.position.y = 0;
        }
      }

      // Animate viewer highlight pulse
      if (figure.userData.isViewer && figure.userData.viewerHighlight) {
        const pulse = 0.7 + Math.sin(time * 3) * 0.3;
        figure.userData.viewerHighlight.children.forEach(child => {
          if (child.material) {
            child.material.opacity = child.userData?.baseOpacity
              ? child.userData.baseOpacity * pulse
              : pulse * 0.5;
          }
        });
      }

      // Animate halo rotation
      if (figure.userData.halo) {
        figure.userData.halo.rotation.y = time * 0.5;
      }

      // Animate seller badge bobbing
      if (figure.userData.sellerBadge) {
        figure.userData.sellerBadge.position.y = 2.8 + Math.sin(time * 2) * 0.1;
        figure.userData.sellerBadge.rotation.y = time;
      }

      // Animate conversation indicator
      if (figure.userData.conversationIndicator && figure.userData.conversationIndicator.visible) {
        const indicator = figure.userData.conversationIndicator;

        // Gentle bobbing
        indicator.position.y = Math.sin(time * 1.5) * 0.05;

        // Animate typing dots if typing
        if (indicator.userData.isTyping) {
          indicator.children.forEach(child => {
            if (child.userData && child.userData.dotIndex !== undefined) {
              const dotTime = time * 4 + child.userData.dotIndex * 0.5;
              child.position.y = 2.5 + Math.sin(dotTime) * 0.05;
              child.material.opacity = 0.5 + Math.sin(dotTime) * 0.5;
            }
          });
        }
      }

      // Animate message indicator (pulsing)
      if (figure.userData.messageIndicator && figure.userData.messageIndicator.visible) {
        const indicator = figure.userData.messageIndicator;
        const pulse = 0.7 + Math.sin(time * 4) * 0.3;
        const scale = 0.9 + Math.sin(time * 3) * 0.2;

        indicator.children.forEach(child => {
          if (child.material && child.material.color) {
            // Pulse the red circle
            if (child.material.color.getHex() === 0xff4444) {
              child.material.opacity = pulse;
            }
          }
        });
        indicator.scale.set(scale, scale, 1);
      }

      // Animate appear effect (scale up)
      if (figure.userData.appearAnimation) {
        const anim = figure.userData.appearAnimation;
        const elapsed = performance.now() - anim.startTime;
        const progress = Math.min(elapsed / anim.duration, 1);

        // Ease out elastic for bouncy appear
        const eased = 1 - Math.pow(1 - progress, 3);
        figure.scale.set(eased, eased, eased);

        if (progress >= 1) {
          figure.scale.set(1, 1, 1);
          delete figure.userData.appearAnimation;
        }
      }

      // Animate disappear effect (scale down + fade)
      if (figure.userData.disappearAnimation) {
        const anim = figure.userData.disappearAnimation;
        const elapsed = performance.now() - anim.startTime;
        const progress = Math.min(elapsed / anim.duration, 1);

        // Scale down and move up (beam out)
        const scale = 1 - progress;
        figure.scale.set(scale, 1 + progress * 2, scale);
        figure.position.y = progress * 5;

        // Fade out all materials
        figure.traverse(child => {
          if (child.material && child.material.opacity !== undefined) {
            child.material.transparent = true;
            child.material.opacity = 1 - progress;
          }
        });

        if (progress >= 1) {
          figure.visible = false;
          delete figure.userData.disappearAnimation;
        }
      }
    });


    // Animate target indicator
    if (targetIndicator.visible) {
      targetIndicator.rotation.y = time * 2;
      const scale = 1 + Math.sin(time * 4) * 0.2;
      targetIndicator.scale.set(scale, 1, scale);
    }

    renderer.render(scene, camera);
  }

  animate();

  // Handle resize
  function onWindowResize() {
    const newWidth = container.clientWidth;
    const newHeight = container.clientHeight;
    const newAspect = newWidth / newHeight;

    camera.left = -viewSize * newAspect / 2;
    camera.right = viewSize * newAspect / 2;
    camera.top = viewSize / 2;
    camera.bottom = -viewSize / 2;
    camera.updateProjectionMatrix();

    renderer.setSize(newWidth, newHeight);
  }

  window.addEventListener("resize", onWindowResize);

  // Keyboard controls - attach to document for reliable capture
  function onKeyDown(event) {
    // Only handle if not typing in an input
    if (event.target.tagName === "INPUT" || event.target.tagName === "TEXTAREA") {
      return;
    }

    let handled = false;
    switch (event.code) {
      case "KeyW":
      case "ArrowUp":
        movement.keys.up = true;
        handled = true;
        break;
      case "KeyS":
      case "ArrowDown":
        movement.keys.down = true;
        handled = true;
        break;
      case "KeyA":
      case "ArrowLeft":
        movement.keys.left = true;
        handled = true;
        break;
      case "KeyD":
      case "ArrowRight":
        movement.keys.right = true;
        handled = true;
        break;
    }

    if (handled) {
      event.preventDefault();
      event.stopPropagation();
    }
  }

  function onKeyUp(event) {
    switch (event.code) {
      case "KeyW":
      case "ArrowUp":
        movement.keys.up = false;
        break;
      case "KeyS":
      case "ArrowDown":
        movement.keys.down = false;
        break;
      case "KeyA":
      case "ArrowLeft":
        movement.keys.left = false;
        break;
      case "KeyD":
      case "ArrowRight":
        movement.keys.right = false;
        break;
    }
  }

  // Attach to document with capture phase to get events first
  document.addEventListener("keydown", onKeyDown, true);
  document.addEventListener("keyup", onKeyUp, true);

  // Raycasting for click detection
  const raycaster = new THREE.Raycaster();
  const mouse = new THREE.Vector2();

  function onMouseClick(event) {
    const rect = renderer.domElement.getBoundingClientRect();
    mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    raycaster.setFromCamera(mouse, camera);
    const intersects = raycaster.intersectObjects(scene.children, true);

    for (const intersect of intersects) {
      let obj = intersect.object;

      // Check if clicked on ground
      while (obj) {
        if (obj.userData.isGround) {
          const point = intersect.point;

          // If in place mode, place an object instead of moving
          if (placeModeEnabled && config.onPlaceObject) {
            config.onPlaceObject(point.x, point.z);
            return;
          }

          // Send move-to intent to server
          if (config.onMoveTo) {
            config.onMoveTo(point.x, point.z);
          }
          targetIndicator.position.set(point.x, 0, point.z);
          targetIndicator.visible = true;
          // Hide after a short delay
          setTimeout(() => { targetIndicator.visible = false; }, 500);
          return;
        }

        if (obj.userData.user) {
          // Clicked on a user
          if (!obj.userData.user.isViewer && config.onUserClick) {
            config.onUserClick(obj.userData.user);
          }
          return;
        }

        obj = obj.parent;
      }
    }
  }

  renderer.domElement.addEventListener("click", onMouseClick);


  // Public API for updating users from LiveView
  function updateUsers(newUsers) {
    config.users = newUsers;
    updateInfoPanel();
  }

  // Update all entities from server (full world state)
  function updateEntities(entities) {
    console.log("[neighborhood] updateEntities received:", entities.length, "entities");
    console.log("[neighborhood] entity IDs:", entities.map(e => e.id));

    const existingIds = new Set(figures.map(f => f.userData.user?.id));
    const newIds = new Set(entities.map(e => e.id));

    console.log("[neighborhood] existing figure IDs:", Array.from(existingIds));
    console.log("[neighborhood] new entity IDs:", Array.from(newIds));

    // Add figures for new entities
    entities.forEach(entity => {
      entityPositions.set(entity.id, { x: entity.position.x, z: entity.position.z });

      if (!existingIds.has(entity.id)) {
        // New entity - create a figure for it
        const user = {
          id: entity.id,
          name: entity.name || entity.display_name,
          display_name: entity.display_name || entity.name,
          color: entity.color,
          position: entity.position,
          connections: entity.connections || [],
          isViewer: entity.isViewer || false,
          verificationLevel: entity.verificationLevel || 0,
          hasProducts: entity.hasProducts || false
        };
        const opacity = getOpacity(viewer, user);
        const figure = createFigure(user, opacity);
        figures.push(figure);
        scene.add(figure);

        // Update viewerFigure if this is the viewer
        if (user.isViewer) {
          viewerFigure = figure;
        }
      }
    });

    // Remove figures for entities that left
    for (let i = figures.length - 1; i >= 0; i--) {
      const figure = figures[i];
      const userId = figure.userData.user?.id;
      if (userId && !newIds.has(userId)) {
        scene.remove(figure);
        figures.splice(i, 1);
        entityPositions.delete(userId);
      }
    }

    // Update the users array for info panel
    config.users = entities.map(entity => ({
      id: entity.id,
      name: entity.name || entity.display_name,
      display_name: entity.display_name || entity.name,
      color: entity.color,
      position: entity.position,
      connections: entity.connections || [],
      isViewer: entity.isViewer || false,
      verificationLevel: entity.verificationLevel || 0,
      hasProducts: entity.hasProducts || false
    }));

    updateInfoPanel();
  }

  // Update a single user's position (called from LiveView)
  function updateUserPosition(userId, position, teleport = false) {
    console.log("[neighborhood] updateUserPosition:", userId, position, teleport ? "(teleport)" : "");
    entityPositions.set(userId, { x: position.x, z: position.z });

    // If we don't have a figure for this user yet, we'll create one
    // This can happen if position updates arrive before world_update
    const existingFigure = figures.find(f => f.userData.user?.id === userId);
    if (!existingFigure) {
      console.log("[neighborhood] Creating figure for unknown user:", userId);
      // Create a basic figure with placeholder data
      const user = {
        id: userId,
        name: userId,
        display_name: userId,
        color: "#888888",
        position: position,
        connections: [],
        isViewer: false,
        verificationLevel: 0,
        hasProducts: false
      };
      const figure = createFigure(user, 0.4);
      figures.push(figure);
      scene.add(figure);
    } else if (teleport) {
      // For teleport (travel), immediately snap to position
      existingFigure.position.x = position.x;
      existingFigure.position.z = position.z;
    }

    // If this is the viewer and it's a teleport, pan camera to follow
    if (existingFigure && existingFigure.userData.isViewer && teleport) {
      cameraPanTarget = { x: position.x, z: position.z };
    }
  }

  // Teleport all entities to new positions (used during travel)
  function teleportEntities(entities) {
    console.log("[neighborhood] teleportEntities:", entities.length, "entities");

    entities.forEach(entity => {
      entityPositions.set(entity.id, { x: entity.position.x, z: entity.position.z });

      const figure = figures.find(f => f.userData.user?.id === entity.id);
      if (figure) {
        // Immediately snap to new position
        figure.position.x = entity.position.x;
        figure.position.z = entity.position.z;

        // Pan to viewer
        if (figure.userData.isViewer) {
          cameraPanTarget = { x: entity.position.x, z: entity.position.z };
        }
      }
    });
  }

  // Show user appearing animation (beam in effect)
  function showUserAppear(userId) {
    const figure = figures.find(f => f.userData.user?.id === userId);
    if (figure) {
      // Reset visibility and start appear animation
      figure.visible = true;
      figure.userData.appearAnimation = { startTime: performance.now(), duration: 1000 };
      figure.scale.set(0.1, 0.1, 0.1);
      console.log("[neighborhood] User appearing:", userId);
    }
  }

  // Show user disappearing animation (beam out effect)
  function showUserDisappear(userId) {
    const figure = figures.find(f => f.userData.user?.id === userId);
    if (figure) {
      figure.userData.disappearAnimation = { startTime: performance.now(), duration: 800 };
      console.log("[neighborhood] User disappearing:", userId);
    }
  }

  // Initialize positions from initial user data
  users.forEach(user => {
    if (user.position) {
      entityPositions.set(user.id, { x: user.position.x, z: user.position.z });
    }
  });

  // Pan camera to a world position
  function panToPosition(x, z) {
    cameraPanTarget = { x, z };
  }

  // Set conversation state for a user
  function setUserConversationState(userId, inConversation, isTyping = false) {
    const figure = figures.find(f => f.userData.user?.id === userId);
    if (figure && figure.userData.conversationIndicator) {
      const indicator = figure.userData.conversationIndicator;
      indicator.visible = inConversation || isTyping;
      indicator.userData.inConversation = inConversation;
      indicator.userData.isTyping = isTyping;

      // Update dot visibility based on typing
      indicator.children.forEach(child => {
        if (child.userData && child.userData.dotIndex !== undefined) {
          child.visible = isTyping;
        }
      });
    }
  }

  // Set typing state for a user
  function setUserTyping(userId, isTyping) {
    const figure = figures.find(f => f.userData.user?.id === userId);
    if (figure && figure.userData.conversationIndicator) {
      const indicator = figure.userData.conversationIndicator;
      indicator.userData.isTyping = isTyping;
      if (isTyping) {
        indicator.visible = true;
      }

      // Update dot visibility
      indicator.children.forEach(child => {
        if (child.userData && child.userData.dotIndex !== undefined) {
          child.visible = isTyping;
        }
      });
    }
  }

  // Set message notification indicator for a user
  function setUserHasMessage(userId, hasMessage) {
    const figure = figures.find(f => f.userData.user?.id === userId);
    if (figure && figure.userData.messageIndicator) {
      const indicator = figure.userData.messageIndicator;
      indicator.visible = hasMessage;
      indicator.userData.hasMessage = hasMessage;
    }
  }

  // Return cleanup function and API for LiveView hook integration
  return {
    cleanup: function() {
      window.removeEventListener("resize", onWindowResize);
      document.removeEventListener("keydown", onKeyDown, true);
      document.removeEventListener("keyup", onKeyUp, true);
      renderer.domElement.removeEventListener("click", onMouseClick);
      if (animationId) {
        cancelAnimationFrame(animationId);
      }
      renderer.dispose();
      scene.clear();
      if (container.contains(renderer.domElement)) {
        container.removeChild(renderer.domElement);
      }
    },
    updateUsers: updateUsers,
    updateEntities: updateEntities,
    updateUserPosition: updateUserPosition,
    panToPosition: panToPosition,
    getViewerPosition: () => viewerFigure ? { x: viewerFigure.position.x, z: viewerFigure.position.z } : null,
    // New APIs for travel and objects
    updateLocation: updateLocation,
    teleportEntities: teleportEntities,
    createBoundaryLines: createBoundaryLines,
    addWorldObject: addWorldObject,
    removeWorldObject: removeWorldObject,
    updateWorldObject: updateWorldObject,
    setPlaceMode: setPlaceMode,
    // Conversation indicators
    setUserConversationState: setUserConversationState,
    setUserTyping: setUserTyping,
    setUserHasMessage: setUserHasMessage,
    // Travel animations
    showUserAppear: showUserAppear,
    showUserDisappear: showUserDisappear
  };
}
