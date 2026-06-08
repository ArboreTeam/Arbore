export function generateStaticParams() {
  return [
    { id: '1' },
    { id: '2' },
    { id: '3' },
    { id: '5' },
    { id: '6' },
  ];
}

export default function PlantLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return children;
}
