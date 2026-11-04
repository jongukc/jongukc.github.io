const toggle = document.getElementById("toggle_dark_mode");

const getIsDark = () => {
    const stored = localStorage.getItem('darkmode');
    if (stored) return stored === 'dark';
    return matchMedia('(prefers-color-scheme: dark)').matches;
};

const setTheme = (isDark) => {
    const theme = isDark ? 'dark' : 'light';
    document.documentElement.setAttribute('color-theme', theme);
    localStorage.setItem('darkmode', theme);
};

if (toggle) {
    toggle.checked = getIsDark();
    toggle.addEventListener('change', (e) => setTheme(e.target.checked));
}

matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
    if (!localStorage.getItem('darkmode')) {
        if (toggle) toggle.checked = e.matches;
    }
});
