import { ReactNode } from 'react';

interface SectionTitleProps {
  children: ReactNode;
  subtitle?: string;
  centered?: boolean;
}

export function SectionTitle({ children, subtitle, centered = true }: SectionTitleProps) {
  return (
    <div className={centered ? 'text-center' : ''}>
      <h2 className="text-3xl md:text-4xl font-bold text-[#2D5A27] mb-4">
        {children}
      </h2>
      {subtitle && (
        <p className="text-lg text-gray-600 max-w-2xl mx-auto">
          {subtitle}
        </p>
      )}
    </div>
  );
}
