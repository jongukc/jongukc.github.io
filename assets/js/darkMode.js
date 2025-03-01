const theme = [...document.styleSheets].find(style => /(style.css)$/.test(style.href));

let setDarkMode = (isDark) => {
    console.log("setDarkMode: ", isDark ? "true" : "false");
    document.documentElement.setAttribute('color-theme', isDark ? "dark" : "light");
    localStorage.setItem('darkmode', isDark ? 'dark' : 'light');
    //localStorage.clear();
}

let currentTheme = localStorage.getItem('darkmode');
let isDarkMode = false;
if (currentTheme) {
    isDarkMode = currentTheme === 'dark';
} else {
    isDarkMode = matchMedia('(prefers-color-scheme: dark)').matches;
}

setDarkMode(isDarkMode);

let toggleThemeBtn = document.getElementById("toggle_dark_mode")
if (toggleThemeBtn) {
    toggleThemeBtn.checked = isDarkMode
}

let changeTheme = (e) => {
    setDarkMode(e.target.checked);
}

toggleThemeBtn.addEventListener('click', changeTheme)
