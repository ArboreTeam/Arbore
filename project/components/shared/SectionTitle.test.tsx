import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { SectionTitle } from './SectionTitle';

describe('SectionTitle', () => {
  it('rend le titre passé en children', () => {
    render(<SectionTitle>Mon titre</SectionTitle>);
    expect(screen.getByRole('heading', { name: 'Mon titre' })).toBeInTheDocument();
  });

  it('affiche le sous-titre quand il est fourni', () => {
    render(<SectionTitle subtitle="Un sous-titre">Titre</SectionTitle>);
    expect(screen.getByText('Un sous-titre')).toBeInTheDocument();
  });

  it("n'affiche aucun sous-titre par défaut", () => {
    render(<SectionTitle>Titre</SectionTitle>);
    expect(screen.queryByText('Un sous-titre')).not.toBeInTheDocument();
  });
});
