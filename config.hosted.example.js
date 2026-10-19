// LOCAL TEST AGAINST THE HOSTED PROJECT (never deployed: only loaded on localhost with ?cfg=hosted).
// 1) cp config.hosted.example.js config.local.hosted.js   2) paste the publishable key (sb_publishable_…) below   3) open http://localhost:8080/index.html?cfg=hosted
// NEVER paste a secret / service_role key. config.local.hosted.js is git-ignored.
window.SUPABASE_CONFIG = {
  url: 'https://oxqcprgreelxfjhlqpxl.supabase.co',
  publishableKey: 'PASTE_YOUR_SUPABASE_PUBLISHABLE_KEY_HERE',
  syncEnabled: true
};
