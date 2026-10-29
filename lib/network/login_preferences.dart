/// Only defaults the source site's existing remember-login control. The site
/// still sets cookie lifetime, and a user's later choice is left untouched.
const rememberLoginScript = r'''
(() => {
  const url = new URL(location.href);
  if (url.protocol !== 'https:' || url.hostname !== 'www.chiphell.com' ||
      url.pathname !== '/member.php' || url.searchParams.get('mod') !== 'logging' ||
      url.searchParams.get('action') !== 'login') return;
  const apply = () => {
    document.querySelectorAll('input[type="checkbox"][name="cookietime"]').forEach(input => {
      if (input.disabled || input.dataset.chhRememberDefault || !(Number(input.value) > 0)) return;
      input.dataset.chhRememberDefault = '1';
      input.checked = true;
    });
  };
  apply();
  new MutationObserver(apply).observe(document.documentElement, {childList: true, subtree: true});
})();
''';
