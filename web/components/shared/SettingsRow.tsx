import Link from 'next/link';
import type { LucideIcon } from 'lucide-react';
import { ChevronRight } from 'lucide-react';
import type { ReactNode } from 'react';

export type Tone = 'green' | 'gold' | 'sage' | 'success' | 'danger' | 'muted';

const TONE: Record<Tone, { text: string; bg: string }> = {
  green: { text: 'text-arbore-green', bg: 'bg-arbore-green/15' },
  gold: { text: 'text-arbore-gold', bg: 'bg-arbore-gold/15' },
  sage: { text: 'text-arbore-sage', bg: 'bg-arbore-sage/25' },
  success: { text: 'text-arbore-success', bg: 'bg-arbore-success/15' },
  danger: { text: 'text-arbore-danger', bg: 'bg-arbore-danger/15' },
  muted: { text: 'text-arbore-muted', bg: 'bg-arbore-muted/15' },
};

/** Badge icône teinté 42×42 (façon SettingsIconBadge iOS). */
export function IconBadge({
  icon: Icon,
  tone = 'green',
  className = '',
}: {
  icon: LucideIcon;
  tone?: Tone;
  className?: string;
}) {
  const t = TONE[tone];
  return (
    <div className={`flex h-[42px] w-[42px] flex-shrink-0 items-center justify-center rounded-[14px] ${t.bg} ${className}`}>
      <Icon className={`h-[18px] w-[18px] ${t.text}`} strokeWidth={2.2} />
    </div>
  );
}

/** Ligne de réglage : badge + titre (+ sous-titre) + chevron, sur carte blanche (façon SettingsRow iOS). */
export function SettingsRow({
  icon,
  tone = 'green',
  title,
  subtitle,
  href,
  onClick,
  danger = false,
  trailing,
}: {
  icon: LucideIcon;
  tone?: Tone;
  title: string;
  subtitle?: string;
  href?: string;
  onClick?: () => void;
  danger?: boolean;
  trailing?: ReactNode;
}) {
  const cls =
    'flex w-full items-center gap-4 rounded-card border border-border bg-card p-4 text-left shadow-soft transition hover:shadow-card';
  const inner = (
    <>
      <IconBadge icon={icon} tone={danger ? 'danger' : tone} />
      <div className="min-w-0 flex-1">
        <p className={`font-semibold ${danger ? 'text-arbore-danger' : 'text-arbore-ink'}`}>{title}</p>
        {subtitle && <p className="mt-0.5 line-clamp-2 text-xs text-arbore-muted">{subtitle}</p>}
      </div>
      {trailing ?? <ChevronRight className="h-4 w-4 flex-shrink-0 text-arbore-muted" />}
    </>
  );

  if (href) {
    const external = href.startsWith('http');
    if (external) {
      return (
        <a href={href} target="_blank" rel="noopener noreferrer" className={cls}>
          {inner}
        </a>
      );
    }
    return (
      <Link href={href} className={cls}>
        {inner}
      </Link>
    );
  }
  return (
    <button type="button" onClick={onClick} className={cls}>
      {inner}
    </button>
  );
}

/** Titre de section (façon sectionTitle iOS). */
export function SectionHeader({ children }: { children: ReactNode }) {
  return <h2 className="mb-3 px-1 font-display text-lg font-bold text-arbore-ink">{children}</h2>;
}
