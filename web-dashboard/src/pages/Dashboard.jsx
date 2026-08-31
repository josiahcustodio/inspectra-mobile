import { Bell, Search } from 'lucide-react';
import StatusHub from '../components/StatusHub';
import NewInspectionButton from '../components/NewInspectionButton';
import RecentActivity from '../components/RecentActivity';

function Header() {
  return (
    <header className="pt-24 pb-8 flex items-center justify-between z-10 relative">
      <div>
        <h1 className="text-3xl font-bold text-white tracking-tight">Inspector</h1>
        <p className="text-sm text-emerald-400">Welcome back, Agent</p>
      </div>
      <div className="flex items-center gap-3">
        <button className="w-10 h-10 rounded-full glass-card flex items-center justify-center text-white hover:bg-white/20 transition-colors">
          <Search className="w-5 h-5" />
        </button>
        <button className="w-10 h-10 rounded-full glass-card flex items-center justify-center text-white relative hover:bg-white/20 transition-colors">
          <span className="absolute top-2 right-2 w-2 h-2 bg-red-500 rounded-full animate-pulse" />
          <Bell className="w-5 h-5" />
        </button>
      </div>
    </header>
  );
}

export default function Dashboard() {
  return (
    <div className="px-4 pb-32 h-screen overflow-y-auto scrollbar-hide" style={{ scrollbarWidth: 'none', msOverflowStyle: 'none' }}>
      <Header />
      <div className="space-y-8 mt-6">
        <StatusHub />
        <NewInspectionButton />
        <RecentActivity />
      </div>
    </div>
  );
}
