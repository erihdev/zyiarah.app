// Central role → page access map for the admin panel. Kept in sync with
// firestore.rules and the Cloud Functions' _assertAdmin checks so a role never
// sees a page whose actions the backend would reject. super_admin / admin have
// full access. The backend remains the real security boundary — this is UX gating.

export const PAGE_ROLES: Record<string, string[]> = {
  '/':                 ['super_admin', 'admin', 'orders_manager', 'accountant_admin', 'marketing_admin'],
  '/orders':           ['super_admin', 'admin', 'orders_manager'],
  '/contracts':        ['super_admin', 'admin', 'orders_manager'],
  '/store-products':   ['super_admin', 'admin', 'marketing_admin'],
  '/store-orders':     ['super_admin', 'admin', 'orders_manager'],
  '/drivers':          ['super_admin', 'admin', 'orders_manager'],
  '/users':            ['super_admin', 'admin', 'orders_manager'],
  '/accountants':      ['super_admin', 'admin', 'accountant_admin'],
  '/payroll':          ['super_admin', 'admin', 'accountant_admin'],
  '/marketing':        ['super_admin', 'admin', 'marketing_admin'],
  '/support':          ['super_admin', 'admin', 'orders_manager'],
  '/account-deletion': ['super_admin', 'admin'],
  '/admins':           ['super_admin', 'admin'],
  '/notifications':    ['super_admin', 'admin', 'orders_manager', 'marketing_admin'],
  '/settings':         ['super_admin', 'admin'],
};

export function canAccess(role: string | null | undefined, path: string): boolean {
  if (!role) return false;
  if (role === 'super_admin' || role === 'admin') return true;
  const allowed = PAGE_ROLES[path];
  return allowed ? allowed.includes(role) : false;
}
