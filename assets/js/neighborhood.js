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
  const groundMaterial = new THREE.MeshStandardMaterial({
    color: 0x3d5c3d,
    roughness: 0.9
  });
  const ground = new THREE.Mesh(groundGeometry, groundMaterial);
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  ground.userData.isGround = true;
  scene.add(ground);

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

  // Street creation
  function createStreet(x, z, streetWidth, length, vertical = false) {
    const streetGeometry = new THREE.PlaneGeometry(
      vertical ? streetWidth : length,
      vertical ? length : streetWidth
    );
    const streetMaterial = new THREE.MeshStandardMaterial({
      color: 0x444444,
      roughness: 0.8
    });
    const street = new THREE.Mesh(streetGeometry, streetMaterial);
    street.rotation.x = -Math.PI / 2;
    street.position.set(x, 0.01, z);
    street.receiveShadow = true;
    street.userData.isGround = true;
    return street;
  }

  // Create neighborhood streets (grid pattern)
  const streetWidth = 8;
  const blockSize = 40;

  // Main horizontal streets
  scene.add(createStreet(0, -blockSize / 2, streetWidth, 180, false));
  scene.add(createStreet(0, blockSize / 2, streetWidth, 180, false));

  // Vertical streets
  scene.add(createStreet(-blockSize, 0, streetWidth, 100, true));
  scene.add(createStreet(0, 0, streetWidth, 100, true));
  scene.add(createStreet(blockSize, 0, streetWidth, 100, true));

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
    building.userData.isBuilding = true;
    return building;
  }

  // Seed buildings in blocks
  const buildingColors = [0x8b7355, 0xa0936e, 0xc4b7a6, 0x9a8b7a, 0xb8a080];

  function seedBlock(centerX, centerZ, seed) {
    seedCounter = seed;
    const buildingCount = 3 + Math.floor(random() * 3);

    for (let i = 0; i < buildingCount; i++) {
      const bx = centerX + (random() - 0.5) * 28;
      const bz = centerZ + (random() - 0.5) * 28;
      const bw = 6 + random() * 8;
      const bd = 6 + random() * 8;
      const bh = 4 + random() * 8;
      const color = buildingColors[Math.floor(random() * buildingColors.length)];

      scene.add(createBuilding(bx, bz, bw, bd, bh, color));
    }
  }

  // Create 4 blocks
  seedBlock(-blockSize / 2, -blockSize, 1001);
  seedBlock(blockSize / 2, -blockSize, 1002);
  seedBlock(-blockSize / 2, blockSize, 1003);
  seedBlock(blockSize / 2, blockSize, 1004);

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

  function animate() {
    animationId = requestAnimationFrame(animate);

    const now = performance.now();
    const delta = (now - lastTime) / 1000; // seconds
    lastTime = now;

    time += delta;

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

      // Check if clicked on ground for movement
      while (obj) {
        if (obj.userData.isGround) {
          // Send move-to intent to server
          const point = intersect.point;
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
  function updateUserPosition(userId, position) {
    console.log("[neighborhood] updateUserPosition:", userId, position);
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
    }
  }

  // Initialize positions from initial user data
  users.forEach(user => {
    if (user.position) {
      entityPositions.set(user.id, { x: user.position.x, z: user.position.z });
    }
  });

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
    getViewerPosition: () => viewerFigure ? { x: viewerFigure.position.x, z: viewerFigure.position.z } : null
  };
}
