import { Navbar } from '@/components/shared/Navbar';
import { Footer } from '@/components/shared/Footer';
import { HeroSection } from '@/components/home/HeroSection';
import { ProblemsSection } from '@/components/home/ProblemsSection';
import { SolutionSection } from '@/components/home/SolutionSection';
import { HowItWorksSection } from '@/components/home/HowItWorksSection';
import { Button } from '@/components/ui/button';

export default function Home() {
  return (
    <main>
      <Navbar />
      <HeroSection />
      <ProblemsSection />
      <SolutionSection />
      <HowItWorksSection />
      <Footer />
    </main>
  );
}
