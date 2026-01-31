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
 */

export function renderNeighborhood(containerId) {
  const container = document.getElementById(containerId);
  if (!container) return null;

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
  // Position camera at equal distances on X, Y, Z
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
  function createStreet(x, z, width, length, vertical = false) {
    const streetGeometry = new THREE.PlaneGeometry(
      vertical ? width : length,
      vertical ? length : width
    );
    const streetMaterial = new THREE.MeshStandardMaterial({
      color: 0x444444,
      roughness: 0.8
    });
    const street = new THREE.Mesh(streetGeometry, streetMaterial);
    street.rotation.x = -Math.PI / 2;
    street.position.set(x, 0.01, z);
    street.receiveShadow = true;
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

  // User/Figure data
  const users = [
    {
      id: "viewer",
      name: "You",
      website: "https://yoursite.example",
      position: { x: -5, z: 0 },
      color: 0x4a90d9,
      connections: ["alice"],
      isViewer: true
    },
    {
      id: "alice",
      name: "Alice",
      website: "https://alice.example.com",
      position: { x: 5, z: 3 },
      color: 0xd94a8a,
      connections: ["viewer"]
    },
    {
      id: "bob",
      name: "Bob",
      website: "https://bob.example.com",
      position: { x: 15, z: -5 },
      color: 0x8ad94a,
      connections: []
    },
    {
      id: "carol",
      name: "Carol",
      website: "https://carol.example.com",
      position: { x: -12, z: 8 },
      color: 0xd9a84a,
      connections: []
    }
  ];

  // Determine visibility/opacity based on connections
  function getOpacity(viewer, subject) {
    if (subject.isViewer) return 1.0;
    if (viewer.connections.includes(subject.id)) return 1.0;
    return 0.4; // Public but not connected
  }

  // Create figure (simple human shape)
  function createFigure(user, opacity) {
    const group = new THREE.Group();

    const bodyMaterial = new THREE.MeshStandardMaterial({
      color: user.color,
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

    group.position.set(user.position.x, 0, user.position.z);
    group.userData = { user: user, opacity: opacity };

    return group;
  }

  // Create all figures
  const viewer = users.find(u => u.isViewer);
  const figures = [];

  users.forEach(user => {
    const opacity = getOpacity(viewer, user);
    const figure = createFigure(user, opacity);
    figures.push(figure);
    scene.add(figure);
  });

  // Update info panel
  const figureListEl = document.getElementById("figure-list");
  if (figureListEl) {
    figureListEl.innerHTML = "";
    users.forEach(user => {
      const opacity = getOpacity(viewer, user);
      const connected = opacity === 1.0;
      const div = document.createElement("div");
      div.style.cssText = `
        padding: 6px 0;
        border-bottom: 1px solid #333;
        opacity: ${opacity};
      `;
      div.innerHTML = `
        <div style="display: flex; align-items: center; gap: 8px;">
          <div style="width: 10px; height: 10px; border-radius: 50%; background: #${user.color.toString(16).padStart(6, '0')};"></div>
          <span>${user.name}</span>
          ${connected && !user.isViewer ? '<span style="color: #4a4; font-size: 10px;">connected</span>' : ''}
          ${user.isViewer ? '<span style="color: #888; font-size: 10px;">you</span>' : ''}
        </div>
        <div style="font-size: 10px; color: #666; margin-top: 2px; margin-left: 18px;">
          ${user.website}
        </div>
      `;
      figureListEl.appendChild(div);
    });
  }

  // Animation state
  let time = 0;
  let animationId = null;
  const walkPaths = users.map((user, i) => ({
    baseX: user.position.x,
    baseZ: user.position.z,
    speed: 0.3 + (i * 0.1),
    radius: 2 + (i * 0.5),
    offset: i * Math.PI / 2
  }));

  function animate() {
    animationId = requestAnimationFrame(animate);

    time += 0.016; // ~60fps

    // Animate figures walking
    figures.forEach((figure, i) => {
      const path = walkPaths[i];
      const walkCycle = time * path.speed + path.offset;

      // Simple circular path
      figure.position.x = path.baseX + Math.sin(walkCycle) * path.radius;
      figure.position.z = path.baseZ + Math.cos(walkCycle) * path.radius;

      // Face direction of movement
      figure.rotation.y = walkCycle + Math.PI;

      // Subtle bobbing
      figure.position.y = Math.abs(Math.sin(walkCycle * 4)) * 0.05;
    });

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

  // Return cleanup function for LiveView hook integration
  return function cleanup() {
    window.removeEventListener("resize", onWindowResize);
    if (animationId) {
      cancelAnimationFrame(animationId);
    }
    renderer.dispose();
    scene.clear();
    if (container.contains(renderer.domElement)) {
      container.removeChild(renderer.domElement);
    }
  };
}
