const defaultTheme = [...document.styleSheets].find(style => /(style.css)$/.test(style.href));
const darkTheme = [...document.styleSheets].find(style => /(style_dark.css)$/.test(style.href));

let setDarkMode = (isDark) => {
    darkTheme.disabled = (isDark !== true);
    defaultTheme.disabled = (isDark === true);
    localStorage.setItem('darkmode', isDark ? 'dark' : 'default');
}

if (true) {
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
        console.log("ASDFASDF")
    }

    toggleThemeBtn.addEventListener('click', changeTheme)
}

