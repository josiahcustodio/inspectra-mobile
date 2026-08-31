import { useRef, useEffect, useState } from 'react';
import { motion, useScroll, useTransform, useSpring } from 'framer-motion';
import { ChevronRight } from 'lucide-react';
import { cn } from '../lib/utils';

const CircularProgress = ({ value, label }) => {
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const timer = setTimeout(() => setProgress(value), 500);
    return () => clearTimeout(timer);
  }, [value]);

  const radius = 24;
  const circumference = 2 * Math.PI * radius;
  const strokeDashoffset = circumference - (progress / 100) * circumference;

  return (
    <div className="relative flex items-center justify-center">
      <svg className="w-16 h-16 transform -rotate-90">
        <circle
          cx="32"
          cy="32"
          r={radius}
          stroke="currentColor"
          strokeWidth="4"
          fill="transparent"
          className="text-white/20"
        />
        <motion.circle
          cx="32"
          cy="32"
          r={radius}
          stroke="currentColor"
          strokeWidth="4"
          fill="transparent"
          className="text-emerald-400"
          strokeDasharray={circumference}
          initial={{ strokeDashoffset: circumference }}
          animate={{ strokeDashoffset }}
          transition={{ duration: 1.5, ease: "easeOut" }}
          strokeLinecap="round"
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center flex-col">
        <span className="text-sm font-bold text-white">{progress}%</span>
      </div>
    </div>
  );
};

const ActivityCard = ({ title, date, score, image, className }) => {
  return (
    <motion.div 
      whileHover={{ scale: 1.02 }}
      className={cn(
        "min-w-[280px] h-40 rounded-3xl relative overflow-hidden flex-shrink-0 group cursor-pointer",
        className
      )}
    >
      {/* Parallax Image Overlay */}
      <div className="absolute inset-0 z-0">
        <div 
          className="absolute inset-0 bg-cover bg-center transition-transform duration-700 ease-out group-hover:scale-110"
          style={{ backgroundImage: `url(${image})` }}
        />
        <div className="absolute inset-0 bg-gradient-to-t from-background via-background/60 to-transparent" />
      </div>

      <div className="relative z-10 p-5 h-full flex items-end justify-between">
        <div>
          <h3 className="text-lg font-bold text-white mb-1">{title}</h3>
          <p className="text-sm text-slate-300">{date}</p>
        </div>
        <CircularProgress value={score} />
      </div>
    </motion.div>
  );
};

export default function RecentActivity() {
  const containerRef = useRef(null);

  return (
    <section className="mt-10 z-10 relative">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-semibold text-white">Recent Activity</h2>
        <button className="text-sm text-primary flex items-center hover:text-emerald-400 transition-colors">
          View All <ChevronRight className="w-4 h-4 ml-1" />
        </button>
      </div>

      <div 
        ref={containerRef}
        className="flex gap-4 overflow-x-auto pb-4 snap-x snap-mandatory scrollbar-hide"
        style={{ scrollbarWidth: 'none', msOverflowStyle: 'none' }}
      >
        <ActivityCard 
          title="Kwatogs Resto" 
          date="Today, 10:30 AM" 
          score={85} 
          image="https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=800&q=80"
          className="snap-center"
        />
        <ActivityCard 
          title="Bakehouse" 
          date="Yesterday, 2:15 PM" 
          score={92} 
          image="https://images.unsplash.com/photo-1556306535-0f09a536f01f?auto=format&fit=crop&w=800&q=80"
          className="snap-center"
        />
        <ActivityCard 
          title="Central Market" 
          date="Mon, 9:00 AM" 
          score={78} 
          image="https://images.unsplash.com/photo-1533900298318-6b8da08a523e?auto=format&fit=crop&w=800&q=80"
          className="snap-center"
        />
      </div>
    </section>
  );
}
