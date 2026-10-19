// Public Supabase settings. The publishable key is safe in the browser (Row Level Security protects the data).
// NEVER put a secret / service_role key here.
window.SUPABASE_CONFIG = {
  url: 'https://oxqcprgreelxfjhlqpxl.supabase.co',
  publishableKey: 'sb_publishable_jzsyiz3ClAJ-7mO_zVOhPQ_gzVWZzrz',
  // Cloud sync is ON: Supabase is the source of truth. Legacy prettyplan.v1* browser data is never read, written or deleted in this mode.
  syncEnabled: true
};
