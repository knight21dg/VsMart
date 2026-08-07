import Nav from "./components/Nav";
import Hero from "./components/Hero";
import AppPreview from "./components/AppPreview";
import HowCreditWorks from "./components/HowCreditWorks";
import VsScore from "./components/VsScore";
import Features from "./components/Features";
import Ecosystem from "./components/Ecosystem";
import CreditDashboard from "./components/CreditDashboard";
import DeliveryNetwork from "./components/DeliveryNetwork";
import Testimonials from "./components/Testimonials";
import BusinessOpportunities from "./components/BusinessOpportunities";
import Faq from "./components/Faq";
import FinalCta from "./components/FinalCta";
import Footer from "./components/Footer";
import ScrollAnimations from "./components/ScrollAnimations";

export default function Home() {
  return (
    <div style={{ overflowX: "hidden" }}>
      <Nav />
      <Hero />
      <AppPreview />
      <HowCreditWorks />
      <VsScore />
      <Features />
      <Ecosystem />
      <CreditDashboard />
      <DeliveryNetwork />
      <Testimonials />
      <BusinessOpportunities />
      <Faq />
      <FinalCta />
      <Footer />
      <ScrollAnimations />
    </div>
  );
}
