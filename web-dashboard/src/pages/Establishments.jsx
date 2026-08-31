import { useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Search, Plus, ChevronRight, Calendar, MapPin, X } from 'lucide-react';
import { cn } from '../lib/utils';
import { Canvas, useFrame } from '@react-three/fiber';
import * as THREE from 'three';

const establishments = [
  { id: '1', name: 'Kwatogs Resto', type: 'Restaurant', score: 94, image: 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=800&q=80', location: 'Downtown Avenue' },
  { id: '2', name: 'Jollibee', type: 'Fast Food', score: 85, image: 'https://images.unsplash.com/photo-1556306535-0f09a536f01f?auto=format&fit=crop&w=800&q=80', location: 'Main Street Mall' },
  { id: '3', name: 'Starbucks', type: 'Cafe', score: 98, image: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=800&q=80', location: 'Westside Business Park' },
  { id: '4', name: 'Local Diner', type: 'Diner', score: 62, image: 'https://images.unsplash.com/photo-1533900298318-6b8da08a523e?auto=format&fit=crop&w=800&q=80', location: 'South Road' },
];

const blocks = [
  { id: 'b1', title: 'Block A: Kitchen Area', date: 'Jul 15, 2026', score: 94, grade: 'Excellent' },
  { id: 'b2', title: 'Block B: Fire Safety', date: 'Jul 10, 2026', score: 88, grade: 'Satisfactory' },
  { id: 'b3', title: 'Block C: Sanitation', date: 'Jul 05, 2026', score: 98, grade: 'Excellent' },
];

function getStatusColor(score) {
  if (score >= 90) return 'text-emerald-400 border-emerald-500/50 shadow-emerald-500/20';
  if (score >= 70) return 'text-amber-400 border-amber-500/50 shadow-amber-500/20';
  return 'text-red-400 border-red-500/50 shadow-red-500/20';
}

function getGradeGradient(grade) {
  if (grade === 'Excellent') return 'from-emerald-500/20 to-teal-500/10 text-emerald-300 border-emerald-500/30';
  if (grade === 'Satisfactory') return 'from-amber-500/20 to-orange-500/10 text-amber-300 border-amber-500/30';
  return 'from-red-500/20 to-rose-500/10 text-red-300 border-red-500/30';
}

// Micro Radial Progress
const MicroProgress = ({ score }) => {
  const radius = 8;
  const circumference = 2 * Math.PI * radius;
  const strokeDashoffset = circumference - (score / 100) * circumference;
  const colorClass = getStatusColor(score).split(' ')[0];

  return (
    <div className="relative w-6 h-6 flex items-center justify-center">
      <svg className="w-full h-full transform -rotate-90">
        <circle cx="12" cy="12" r={radius} stroke="currentColor" strokeWidth="2" fill="transparent" className="text-white/10" />
        <motion.circle
          cx="12" cy="12" r={radius} stroke="currentColor" strokeWidth="2" fill="transparent"
          className={colorClass} strokeDasharray={circumference}
          initial={{ strokeDashoffset: circumference }}
          animate={{ strokeDashoffset }}
          transition={{ duration: 1, ease: "easeOut" }}
          strokeLinecap="round"
        />
      </svg>
    </div>
  );
};

// WebGL Progress Wheel for Detail Header
const WheelShaderMaterial = {
  uniforms: {
    uProgress: { value: 0 },
    uColor: { value: new THREE.Color('#34d399') }, // emerald-400
  },
  vertexShader: `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `,
  fragmentShader: `
    uniform float uProgress;
    uniform vec3 uColor;
    varying vec2 vUv;
    
    #define PI 3.14159265359

    void main() {
      vec2 center = vec2(0.5);
      vec2 pos = vUv - center;
      float radius = length(pos);
      float angle = atan(pos.y, pos.x) + PI/2.0; // Rotate start to top
      if (angle < 0.0) angle += 2.0 * PI;
      
      float normalizedAngle = angle / (2.0 * PI);
      
      // Ring mask
      float ring = smoothstep(0.45, 0.43, radius) * smoothstep(0.35, 0.37, radius);
      
      // Progress mask
      float progressMask = step(normalizedAngle, uProgress);
      
      // Glow effect
      float glow = exp(-pow(radius - 0.4, 2.0) * 100.0) * 0.5;

      vec3 finalColor = uColor * (ring * progressMask + glow * progressMask);
      vec3 bgColor = vec3(1.0, 1.0, 1.0) * 0.1 * ring; // Background track
      
      gl_FragColor = vec4(finalColor + bgColor, max(ring, glow * progressMask));
    }
  `
};

const ProgressWheel = ({ score }) => {
  const materialRef = useRef();
  const targetProgress = score / 100;

  useFrame((state, delta) => {
    if (materialRef.current) {
      // Smooth interpolation to target progress
      materialRef.current.uniforms.uProgress.value += (targetProgress - materialRef.current.uniforms.uProgress.value) * (delta * 2);
    }
  });

  return (
    <mesh>
      <planeGeometry args={[2, 2]} />
      <shaderMaterial
        ref={materialRef}
        args={[WheelShaderMaterial]}
        transparent
        depthWrite={false}
      />
    </mesh>
  );
};

export default function Establishments() {
  const [selectedId, setSelectedId] = useState(null);
  const [isFocused, setIsFocused] = useState(false);

  const selectedItem = establishments.find(e => e.id === selectedId);

  // Stagger animation for list items
  const containerVariants = {
    hidden: { opacity: 0 },
    show: {
      opacity: 1,
      transition: { staggerChildren: 0.1 }
    }
  };

  const itemVariants = {
    hidden: { opacity: 0, y: 20 },
    show: { opacity: 1, y: 0, transition: { type: 'spring', stiffness: 300, damping: 24 } }
  };

  return (
    <div className="px-4 pt-12 pb-32 h-screen overflow-y-auto scrollbar-hide relative z-10" style={{ scrollbarWidth: 'none', msOverflowStyle: 'none' }}>
      
      <AnimatePresence>
        {!selectedId && (
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            className="space-y-6"
          >
            {/* Header & Actions */}
            <div className="flex items-center gap-3">
              <motion.div 
                animate={{ 
                  boxShadow: isFocused ? '0 0 15px rgba(20, 184, 166, 0.5)' : '0 0 0px rgba(0,0,0,0)',
                  borderColor: isFocused ? 'rgba(20, 184, 166, 0.8)' : 'rgba(255, 255, 255, 0.2)'
                }}
                className="flex-1 glass-card rounded-2xl flex items-center px-4 py-3 transition-colors duration-300 border"
              >
                <Search className={cn("w-5 h-5 transition-colors", isFocused ? "text-teal-400" : "text-slate-400")} />
                <input 
                  type="text" 
                  placeholder="Search establishments..." 
                  onFocus={() => setIsFocused(true)}
                  onBlur={() => setIsFocused(false)}
                  className="bg-transparent border-none outline-none text-white ml-3 w-full placeholder:text-slate-500"
                />
              </motion.div>

              <button className="relative w-12 h-12 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-600 flex items-center justify-center text-white overflow-hidden group hover:scale-105 active:scale-95 transition-transform shadow-lg shadow-teal-500/20">
                <div className="absolute inset-0 bg-white/20 translate-y-full rounded-[50%] group-hover:animate-[wave_1s_ease-in-out_infinite]" />
                <Plus className="w-6 h-6 relative z-10" />
              </button>
            </div>

            {/* List */}
            <motion.div 
              variants={containerVariants}
              initial="hidden"
              animate="show"
              className="space-y-4"
            >
              {establishments.map((est) => (
                <motion.div
                  key={est.id}
                  variants={itemVariants}
                  layoutId={`card-${est.id}`}
                  onClick={() => setSelectedId(est.id)}
                  className={cn(
                    "glass-card p-4 rounded-3xl cursor-pointer group hover:bg-white/10 transition-colors border-2 shadow-lg",
                    getStatusColor(est.score)
                  )}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <motion.div layoutId={`image-${est.id}`} className="w-12 h-12 rounded-full overflow-hidden shrink-0">
                        <img src={est.image} alt={est.name} className="w-full h-full object-cover" />
                      </motion.div>
                      <div>
                        <motion.h3 layoutId={`title-${est.id}`} className="text-white font-bold text-lg leading-tight flex items-center gap-2">
                          {est.name}
                          <MicroProgress score={est.score} />
                        </motion.h3>
                        <motion.p layoutId={`subtitle-${est.id}`} className="text-sm text-slate-300">{est.type}</motion.p>
                      </div>
                    </div>
                    <div className="w-8 h-8 rounded-full bg-white/5 flex items-center justify-center group-hover:animate-bounce">
                      <ChevronRight className="w-4 h-4 text-white/50" />
                    </div>
                  </div>
                </motion.div>
              ))}
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Detail View */}
      <AnimatePresence>
        {selectedId && selectedItem && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="absolute inset-0 z-50 bg-background/80 backdrop-blur-xl overflow-y-auto"
          >
            {/* Expanded Header */}
            <motion.div 
              layoutId={`card-${selectedItem.id}`}
              className={cn(
                "relative h-72 w-full rounded-b-[40px] overflow-hidden border-b-2 shadow-2xl",
                getStatusColor(selectedItem.score)
              )}
            >
              <motion.div layoutId={`image-${selectedItem.id}`} className="absolute inset-0">
                <img src={selectedItem.image} alt={selectedItem.name} className="w-full h-full object-cover" />
                <div className="absolute inset-0 bg-gradient-to-t from-slate-900 via-slate-900/60 to-transparent" />
              </motion.div>

              <button 
                onClick={() => setSelectedId(null)}
                className="absolute top-12 left-4 w-10 h-10 rounded-full glass-card flex items-center justify-center text-white hover:bg-white/20 z-10"
              >
                <X className="w-5 h-5" />
              </button>

              <div className="absolute bottom-6 left-6 right-6 flex items-end justify-between z-10">
                <div>
                  <motion.h3 layoutId={`title-${selectedItem.id}`} className="text-3xl font-bold text-white mb-1">
                    {selectedItem.name}
                  </motion.h3>
                  <motion.p layoutId={`subtitle-${selectedItem.id}`} className="text-slate-300 flex items-center gap-1">
                    <MapPin className="w-4 h-4" /> {selectedItem.location}
                  </motion.p>
                </div>
                
                {/* WebGL Progress Wheel */}
                <div className="w-24 h-24 relative">
                  <Canvas camera={{ position: [0, 0, 2] }} gl={{ alpha: true }}>
                    <ProgressWheel score={selectedItem.score} />
                  </Canvas>
                  <div className="absolute inset-0 flex items-center justify-center flex-col">
                    <span className="text-2xl font-mono font-bold text-white">{selectedItem.score}</span>
                  </div>
                </div>
              </div>
            </motion.div>

            {/* Blocks Feed */}
            <div className="p-4 space-y-4 pb-32">
              <h4 className="text-lg font-semibold text-white mt-4 mb-2">Block Breakdown</h4>
              <motion.div 
                variants={containerVariants}
                initial="hidden"
                animate="show"
                className="space-y-4"
              >
                {blocks.map((block, i) => (
                  <motion.div 
                    key={block.id}
                    variants={itemVariants}
                    className="glass-card p-4 rounded-2xl flex items-center justify-between"
                  >
                    <div>
                      <h5 className="font-semibold text-white mb-1">{block.title}</h5>
                      <div className="flex items-center gap-2 text-xs text-slate-400">
                        <Calendar className="w-3 h-3" />
                        <span>{block.date}</span>
                      </div>
                    </div>
                    
                    <div className="flex flex-col items-end gap-2">
                      <span className="text-xl font-mono font-bold text-white">{block.score}<span className="text-sm text-slate-500">/100</span></span>
                      <div className={cn("px-2 py-1 rounded-md text-[10px] font-bold uppercase tracking-wider border bg-gradient-to-r", getGradeGradient(block.grade))}>
                        {block.grade}
                      </div>
                    </div>
                  </motion.div>
                ))}
              </motion.div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
      
      {/* Required tailwind CSS classes for dynamic wave animation on + button */}
      <style>{`
        @keyframes wave {
          0% { transform: translateY(100%) scale(1); border-radius: 50%; opacity: 0; }
          50% { opacity: 0.5; }
          100% { transform: translateY(-100%) scale(2); border-radius: 40%; opacity: 0; }
        }
      `}</style>
    </div>
  );
}
