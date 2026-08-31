import { useState } from 'react';
import { Bell, Moon, WifiOff, Shield, ChevronRight, LogOut } from 'lucide-react';
import { cn } from '../lib/utils';

export default function Settings() {
  const [notifications, setNotifications] = useState(true);
  const [darkMode, setDarkMode] = useState(true);
  const [offlineMode, setOfflineMode] = useState(false);

  return (
    <div className="px-4 pt-24 pb-32 h-screen overflow-y-auto scrollbar-hide relative z-10" style={{ scrollbarWidth: 'none', msOverflowStyle: 'none' }}>
      <header className="mb-8">
        <h1 className="text-3xl font-bold text-white tracking-tight">Settings</h1>
        <p className="text-sm text-emerald-400 mt-1">Manage your app preferences</p>
      </header>
      
      <div className="space-y-8">
        {/* Preferences */}
        <div className="space-y-3">
          <h2 className="text-xs font-bold text-emerald-400 uppercase tracking-widest pl-4">Preferences</h2>
          <div className="glass-card rounded-3xl overflow-hidden divide-y divide-white/10">
            <ToggleRow 
              icon={Bell} 
              label="Push Notifications" 
              description="Receive updates on inspections"
              checked={notifications} 
              onChange={setNotifications} 
            />
            <ToggleRow 
              icon={Moon} 
              label="Dark Mode" 
              description="Toggle application theme"
              checked={darkMode} 
              onChange={setDarkMode} 
            />
            <ToggleRow 
              icon={WifiOff} 
              label="Offline Mode" 
              description="Save data locally for sync"
              checked={offlineMode} 
              onChange={setOfflineMode} 
            />
          </div>
        </div>

        {/* Account */}
        <div className="space-y-3">
          <h2 className="text-xs font-bold text-emerald-400 uppercase tracking-widest pl-4">Account</h2>
          <div className="glass-card rounded-3xl overflow-hidden divide-y divide-white/10">
            <ActionRow icon={Shield} label="Privacy & Security" />
            <div className="p-5 flex items-center justify-between cursor-pointer hover:bg-white/5 transition-colors text-red-400 group">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 rounded-full bg-red-500/10 flex items-center justify-center group-hover:scale-110 transition-transform">
                  <LogOut className="w-6 h-6" />
                </div>
                <span className="font-semibold text-lg">Log Out</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function ToggleRow({ icon: Icon, label, description, checked, onChange }) {
  return (
    <div className="p-5 flex items-center justify-between hover:bg-white/5 transition-colors">
      <div className="flex items-center gap-4">
        <div className="w-12 h-12 rounded-full bg-emerald-500/10 flex items-center justify-center">
          <Icon className="w-6 h-6 text-emerald-400" />
        </div>
        <div>
          <div className="font-bold text-white text-base">{label}</div>
          <div className="text-sm text-slate-400 font-medium">{description}</div>
        </div>
      </div>
      <button 
        onClick={() => onChange(!checked)}
        className={cn(
          "w-14 h-8 rounded-full transition-colors relative shadow-inner flex items-center",
          checked ? "bg-emerald-500" : "bg-slate-700"
        )}
      >
        <div className={cn(
          "w-6 h-6 rounded-full bg-white absolute transition-all duration-300 shadow-md",
          checked ? "left-[30px]" : "left-[4px]"
        )} />
      </button>
    </div>
  );
}

function ActionRow({ icon: Icon, label }) {
  return (
    <div className="p-5 flex items-center justify-between cursor-pointer hover:bg-white/5 transition-colors group">
      <div className="flex items-center gap-4">
        <div className="w-12 h-12 rounded-full bg-emerald-500/10 flex items-center justify-center group-hover:scale-110 transition-transform">
          <Icon className="w-6 h-6 text-emerald-400" />
        </div>
        <span className="font-bold text-white text-base">{label}</span>
      </div>
      <ChevronRight className="w-6 h-6 text-slate-400 group-hover:text-emerald-400 transition-colors" />
    </div>
  );
}
