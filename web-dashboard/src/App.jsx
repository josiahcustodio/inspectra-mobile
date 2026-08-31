import { BrowserRouter, Routes, Route } from 'react-router-dom';
import BackgroundShader from './components/BackgroundShader';
import BottomNav from './components/BottomNav';
import Dashboard from './pages/Dashboard';
import Establishments from './pages/Establishments';
import Settings from './pages/Settings';

export default function App() {
  return (
    <BrowserRouter>
      <>
        <BackgroundShader />
        <div className="min-h-screen w-full max-w-md mx-auto relative overflow-hidden">
          
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/establishments/*" element={<Establishments />} />
            <Route path="/settings" element={<Settings />} />
          </Routes>

        <BottomNav />
        </div>
      </>
    </BrowserRouter>
  );
}
