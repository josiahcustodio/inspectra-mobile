import { useEffect, useRef, useState } from 'react';
import { motion, useMotionValue, useTransform, animate } from 'framer-motion';
import { cn } from '../lib/utils';
import { CheckCircle2, Clock, MapPin } from 'lucide-react';

const RollingNumber = ({ value }) => {
  const nodeRef = useRef(null);

  useEffect(() => {
    const node = nodeRef.current;
    if (node) {
      const controls = animate(0, value, {
        duration: 1.5,
        ease: "easeOut",
        onUpdate(v) {
          node.textContent = Math.round(v).toString();
        },
      });
      return () => controls.stop();
    }
  }, [value]);

  return <span ref={nodeRef}>{value}</span>;
};

const TiltCard = ({ children, className }) => {
  const x = useMotionValue(0);
  const y = useMotionValue(0);

  const rotateX = useTransform(y, [-100, 100], [10, -10]);
  const rotateY = useTransform(x, [-100, 100], [-10, 10]);

  function handleMouseMove(event) {
    const rect = event.currentTarget.getBoundingClientRect();
    x.set(event.clientX - rect.left - rect.width / 2);
    y.set(event.clientY - rect.top - rect.height / 2);
  }

  function handleMouseLeave() {
    x.set(0);
    y.set(0);
  }

  return (
    <motion.div
      style={{ rotateX, rotateY, transformPerspective: 800 }}
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
      className={cn(
        "glass-card rounded-2xl p-4 flex flex-col justify-between relative overflow-hidden transition-all duration-300",
        className
      )}
    >
      <div className="absolute inset-0 bg-gradient-to-br from-white/5 to-transparent pointer-events-none" />
      {children}
    </motion.div>
  );
};

export default function StatusHub() {
  return (
    <section className="grid grid-cols-2 gap-4 mt-6 z-10 relative">
      <TiltCard className="border-t-primary/50">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm text-slate-300">Pending</span>
          <div className="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center">
            <Clock className="w-4 h-4 text-primary" />
          </div>
        </div>
        <div className="text-3xl font-mono font-semibold text-white">
          <RollingNumber value={12} />
        </div>
      </TiltCard>
      
      <TiltCard className="border-t-blue-500/50">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm text-slate-300">Completed</span>
          <div className="w-8 h-8 rounded-full bg-blue-500/20 flex items-center justify-center">
            <CheckCircle2 className="w-4 h-4 text-blue-400" />
          </div>
        </div>
        <div className="text-3xl font-mono font-semibold text-white">
          <RollingNumber value={48} />
        </div>
      </TiltCard>

      <TiltCard className="col-span-2 border-t-purple-500/50 flex-row items-center">
        <div>
          <span className="text-sm text-slate-300 block mb-1">Establishments</span>
          <div className="text-2xl font-mono font-semibold text-white">
            <RollingNumber value={104} />
          </div>
        </div>
        <div className="w-12 h-12 rounded-full bg-purple-500/20 flex items-center justify-center ml-auto">
          <MapPin className="w-6 h-6 text-purple-400" />
        </div>
      </TiltCard>
    </section>
  );
}
