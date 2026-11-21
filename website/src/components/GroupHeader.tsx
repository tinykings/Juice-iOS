'use client';

export default function GroupHeader({
  label,
  detail,
  tone,
  onAdd,
  action,
  collapse,
}: {
  label: string;
  detail?: string;
  tone: 'today' | 'overdue' | 'default';
  /** Tapping the header opens the add form for that day. */
  onAdd?: () => void;
  action?: { label: string; onClick: () => void };
  /** Makes the header a disclosure button that shows or hides the group's tasks. */
  collapse?: { expanded: boolean; count: number; controls: string; onToggle: () => void };
}) {
  const text = (
    <>
      <span>{label}</span>
      {detail && (
        <span style={{ fontSize: 13, fontWeight: 500, color: 'var(--muted)' }}>{detail}</span>
      )}
    </>
  );

  return (
    <h2 style={{
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      margin: 0,
      padding: '0 4px',
      minHeight: 28,
      fontSize: tone === 'today' ? 15 : 13,
      fontWeight: 700,
      letterSpacing: '0.01em',
      color: tone === 'overdue' ? 'var(--red)' : tone === 'today' ? 'var(--foreground)' : 'var(--muted)',
    }}>
      {collapse ? (
        <button
          type="button"
          className="group-header-add"
          onClick={collapse.onToggle}
          aria-expanded={collapse.expanded}
          aria-controls={collapse.controls}
          style={{ width: '100%', alignItems: 'center' }}
        >
          <svg
            width="14"
            height="14"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
            viewBox="0 0 24 24"
            aria-hidden="true"
            style={{ transform: collapse.expanded ? 'rotate(90deg)' : 'rotate(0deg)', transition: 'transform 0.15s ease' }}
          >
            <path d="M9 18l6-6-6-6" />
          </svg>
          {text}
          <span style={{ marginLeft: 'auto', fontSize: 12, fontWeight: 600 }}>{collapse.count}</span>
        </button>
      ) : onAdd ? (
        <button
          type="button"
          className="group-header-add"
          onClick={onAdd}
          aria-label={`Add task for ${label}${detail ? `, ${detail}` : ''}`}
        >
          {text}
          <svg className="group-header-add-icon" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2.5" viewBox="0 0 24 24" aria-hidden="true">
            <path d="M12 5v14M5 12h14" />
          </svg>
        </button>
      ) : (
        <span style={{ display: 'inline-flex', alignItems: 'baseline', gap: 8 }}>{text}</span>
      )}
      {action && (
        <button type="button" className="group-header-action" onClick={action.onClick}>
          {action.label}
        </button>
      )}
    </h2>
  );
}
