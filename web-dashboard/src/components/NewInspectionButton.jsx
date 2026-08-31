import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Plus, X, FileText, Camera, Map } from 'lucide-react';
import { cn } from '../lib/utils';

export default function NewInspectionButton() {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <>
      <div className="relative mt-8 z-10 flex justify-center">
        {/* Glow behind button */}
        <div className="absolute inset-0 bg-primary/40 blur-xl rounded-full scale-90 animate-pulse" />
        
        <motion.button
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={() => setIsOpen(true)}
          className={cn(
            "relative flex items-center justify-center gap-2 w-full py-4 rounded-2xl font-semibold text-white overflow-hidden group",
            "bg-gradient-to-r from-primary to-emerald-400 shadow-lg shadow-primary/30"
          )}
        >
          {/* Shimmer effect */}
          <div className="absolute inset-0 -translate-x-full bg-gradient-to-r from-transparent via-white/30 to-transparent group-hover:animate-[shimmer_1.5s_infinite]" />
          <Plus className="w-5 h-5" />
          <span>New Inspection</span>
        </motion.button>
      </div>

      <AnimatePresence>
        {isOpen && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setIsOpen(false)}
              className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50"
            />
            <motion.div
              initial={{ opacity: 0, scale: 0.9, y: 40 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.9, y: 20 }}
              transition={{ type: "spring", damping: 25, stiffness: 300 }}
              className="fixed bottom-0 left-0 right-0 p-6 glass-card rounded-t-3xl z-50 flex flex-col gap-4 border-b-0"
            >
              <div className="flex justify-between items-center mb-4">
                <h2 className="text-xl font-semibold text-white">Create Inspection</h2>
                <button 
                  onClick={() => setIsOpen(false)}
                  className="w-8 h-8 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              <div className="grid grid-cols-3 gap-4">
                {[
                  { icon: FileText, label: "Form", color: "text-blue-400", bg: "bg-blue-400/20" },
                  { icon: Camera, label: "Photo", color: "text-purple-400", bg: "bg-purple-400/20" },
                  { icon: Map, label: "Map", color: "text-emerald-400", bg: "bg-emerald-400/20" },
                ].map((item, i) => (
                  <motion.button
                    key={i}
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                    className="flex flex-col items-center gap-2 p-4 rounded-2xl glass-card hover:bg-white/10"
                  >
                    <div className={cn("w-12 h-12 rounded-full flex items-center justify-center", item.bg)}>
                      <item.icon className={cn("w-6 h-6", item.color)} />
                    </div>
                    <span className="text-xs text-slate-300">{item.label}</span>
                  </motion.button>
                ))}
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </>
  );
}
