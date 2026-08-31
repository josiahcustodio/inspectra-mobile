import { useState } from 'react';
import { motion } from 'framer-motion';
import { Home, ClipboardList, Settings, User, QrCode } from 'lucide-react';
import { Link, useLocation } from 'react-router-dom';
import { cn } from '../lib/utils';

export default function BottomNav() {
  const location = useLocation();
  const currentPath = location.pathname;

  const tabs = [
    { id: 'home', path: '/', icon: Home, label: 'Home' },
    { id: 'establishments', path: '/establishments', icon: ClipboardList, label: 'Tasks' },
    { id: 'scan', path: '/scan', icon: QrCode, isCenter: true },
    { id: 'profile', path: '/profile', icon: User, label: 'Profile' },
    { id: 'settings', path: '/settings', icon: Settings, label: 'Settings' },
  ];

  return (
    <div className="fixed bottom-6 left-4 right-4 z-50">
      <div className="glass-card rounded-3xl p-2 flex items-center justify-between relative shadow-[0_8px_32px_rgba(0,0,0,0.5)]">
        {tabs.map((tab) => {
          if (tab.isCenter) {
            return (
              <div key={tab.id} className="relative -top-6 px-2">
                <div className="absolute inset-0 bg-primary/40 blur-md rounded-full animate-pulse" />
                <button
                  className="relative w-14 h-14 bg-gradient-to-tr from-primary to-emerald-400 rounded-full flex items-center justify-center text-white shadow-xl shadow-primary/30 hover:scale-105 active:scale-95 transition-transform"
                >
                  <tab.icon className="w-6 h-6" />
                </button>
              </div>
            );
          }

          const isActive = currentPath === tab.path || (currentPath.startsWith('/establishments') && tab.id === 'establishments');

          return (
            <Link
              key={tab.id}
              to={tab.path}
              className="relative flex-1 py-3 flex flex-col items-center justify-center gap-1 text-slate-400 hover:text-white transition-colors"
            >
              <div className="relative z-10 flex flex-col items-center">
                <tab.icon className={cn("w-5 h-5 mb-1 transition-colors", isActive ? "text-primary" : "")} />
                <span className={cn("text-[10px] font-medium transition-colors", isActive ? "text-primary" : "")}>
                  {tab.label}
                </span>
              </div>
              
              {isActive && (
                <motion.div
                  layoutId="activeTabIndicator"
                  className="absolute inset-0 bg-white/5 rounded-2xl"
                  initial={false}
                  transition={{ type: "spring", stiffness: 300, damping: 20 }}
                />
              )}
            </Link>
          );
        })}
      </div>
    </div>
  );
}
