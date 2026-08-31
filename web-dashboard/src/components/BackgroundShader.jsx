import { useRef, useMemo } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';

const fragmentShader = `
uniform float uTime;
uniform vec2 uResolution;
uniform vec2 uMouse;

void main() {
    vec2 st = gl_FragCoord.xy / uResolution.xy;
    st.x *= uResolution.x / uResolution.y;

    // Center coordinates
    vec2 center = vec2(0.5 * uResolution.x / uResolution.y, 0.5);
    
    // Add mouse interaction
    vec2 mouse = uMouse;
    vec2 dir = st - mouse;
    float dist = length(dir);
    
    // Soft animated wave
    float wave1 = sin(st.x * 5.0 + uTime * 0.5) * 0.5 + 0.5;
    float wave2 = sin(st.y * 3.0 - uTime * 0.3 + wave1) * 0.5 + 0.5;
    float wave3 = sin((st.x + st.y) * 4.0 + uTime * 0.4) * 0.5 + 0.5;
    
    float composite = (wave1 + wave2 + wave3) / 3.0;
    
    // Smooth mouse ripple
    float ripple = exp(-dist * 3.0) * sin(dist * 10.0 - uTime * 2.0) * 0.1;
    
    // Base colors (Emerald green to deep slate)
    vec3 color1 = vec3(0.019, 0.588, 0.412); // #059669 Emerald
    vec3 color2 = vec3(0.059, 0.090, 0.165); // #0F172A Slate 900
    vec3 color3 = vec3(0.118, 0.161, 0.231); // #1E293B Slate 800
    
    vec3 finalColor = mix(color2, color3, composite + ripple);
    finalColor = mix(finalColor, color1, smoothstep(0.4, 1.0, composite) * 0.3);
    
    // Add subtle glow
    finalColor += vec3(0.01, 0.1, 0.05) * (1.0 - dist * 1.5);

    gl_FragColor = vec4(finalColor, 1.0);
}
`;

const vertexShader = `
void main() {
    gl_Position = vec4(position, 1.0);
}
`;

const ShaderPlane = () => {
  const materialRef = useRef();
  const { size, pointer } = useThree();

  const uniforms = useMemo(
    () => ({
      uTime: { value: 0 },
      uResolution: { value: new THREE.Vector2(size.width, size.height) },
      uMouse: { value: new THREE.Vector2(0.5, 0.5) },
    }),
    []
  );

  useFrame((state) => {
    if (materialRef.current) {
      materialRef.current.uniforms.uTime.value = state.clock.elapsedTime;
      materialRef.current.uniforms.uResolution.value.set(size.width, size.height);
      
      // Map pointer (-1 to 1) to (0 to 1) for shader
      const targetMouseX = (pointer.x + 1) / 2;
      const targetMouseY = (pointer.y + 1) / 2;
      
      // Smooth mouse interpolation
      materialRef.current.uniforms.uMouse.value.x += (targetMouseX - materialRef.current.uniforms.uMouse.value.x) * 0.05;
      materialRef.current.uniforms.uMouse.value.y += (targetMouseY - materialRef.current.uniforms.uMouse.value.y) * 0.05;
    }
  });

  return (
    <mesh>
      <planeGeometry args={[2, 2]} />
      <shaderMaterial
        ref={materialRef}
        vertexShader={vertexShader}
        fragmentShader={fragmentShader}
        uniforms={uniforms}
        depthWrite={false}
        depthTest={false}
      />
    </mesh>
  );
};

export default function BackgroundShader() {
  return (
    <div className="fixed inset-0 w-screen h-screen -z-20 bg-background">
      <Canvas
        camera={{ position: [0, 0, 1] }}
        gl={{ alpha: false, antialias: false, powerPreference: "high-performance" }}
      >
        <ShaderPlane />
      </Canvas>
    </div>
  );
}
