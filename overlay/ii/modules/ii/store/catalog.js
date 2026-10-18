.pragma library

// ii-windows store: the featured apps, by category. Every id is a winget package id (checked against the winget
// catalogue); "site" is where the icon comes from (the site's favicon). Descriptions are kept short on purpose.
var categories = [
    { key: "dev", icon: "terminal", name: "Development", apps: [
        { id: "Microsoft.VisualStudioCode", name: "Visual Studio Code", site: "code.visualstudio.com", desc: "The editor most developers use, with thousands of extensions." },
        { id: "Git.Git", name: "Git", site: "git-scm.com", desc: "Version control, with Git Bash." },
        { id: "GitHub.cli", name: "GitHub CLI", site: "cli.github.com", desc: "GitHub from the terminal: pull requests, issues, releases." },
        { id: "GitHub.GitHubDesktop", name: "GitHub Desktop", site: "desktop.github.com", desc: "Git without the command line." },
        { id: "OpenJS.NodeJS.LTS", name: "Node.js (LTS)", site: "nodejs.org", desc: "JavaScript outside the browser, with npm." },
        { id: "Python.Python.3.12", name: "Python 3.12", site: "python.org", desc: "The Python language and pip." },
        { id: "Rustlang.Rustup", name: "Rust (rustup)", aka: ["rustup", "Rust"], site: "rust-lang.org", desc: "The Rust toolchain installer." },
        { id: "GoLang.Go", name: "Go", site: "go.dev", desc: "The Go language." },
        { id: "Microsoft.DotNet.SDK.9", name: ".NET SDK 9", site: "dotnet.microsoft.com", desc: "Build C#, F# and ASP.NET apps." },
        { id: "Docker.DockerDesktop", name: "Docker Desktop", site: "docker.com", desc: "Containers on your PC." },
        { id: "JetBrains.Toolbox", name: "JetBrains Toolbox", site: "jetbrains.com", desc: "IntelliJ, PyCharm, WebStorm, Rider and the rest." },
        { id: "Google.AndroidStudio", name: "Android Studio", site: "developer.android.com", desc: "Android app development." },
        { id: "Postman.Postman", name: "Postman", site: "postman.com", desc: "Try and document APIs." },
        { id: "DBeaver.DBeaver.Community", name: "DBeaver", site: "dbeaver.io", desc: "One client for every database." },
        { id: "Microsoft.WindowsTerminal", name: "Windows Terminal", site: "microsoft.com", desc: "Tabs and panes for PowerShell, CMD and WSL." },
        { id: "Microsoft.PowerToys", name: "PowerToys", site: "learn.microsoft.com", desc: "Microsoft's utilities: FancyZones, Run, colour picker..." },
        { id: "Neovim.Neovim", name: "Neovim", site: "neovim.io", desc: "The modern Vim." },
        { id: "Notepad++.Notepad++", name: "Notepad++", site: "notepad-plus-plus.org", desc: "Light text editor." },
        { id: "WinSCP.WinSCP", name: "WinSCP", site: "winscp.net", desc: "SFTP and SCP file transfer." },
        { id: "Anysphere.Cursor", name: "Cursor", site: "cursor.com", desc: "A code editor built around AI." }
    ] },
    { key: "web", icon: "language", name: "Browsers", apps: [
        { id: "Mozilla.Firefox", name: "Firefox", site: "firefox.com", desc: "Fast, private and open." },
        { id: "Google.Chrome", name: "Google Chrome", site: "google.com/chrome", desc: "Google's browser." },
        { id: "Brave.Brave", name: "Brave", site: "brave.com", desc: "Blocks ads and trackers by default." },
        { id: "Vivaldi.Vivaldi", name: "Vivaldi", site: "vivaldi.com", desc: "A browser you can customise to the last detail." }
    ] },
    { key: "media", icon: "movie", name: "Media and design", apps: [
        { id: "VideoLAN.VLC", name: "VLC", site: "videolan.org", desc: "Plays almost any video or audio file." },
        { id: "OBSProject.OBSStudio", name: "OBS Studio", site: "obsproject.com", desc: "Record and stream the screen." },
        { id: "Spotify.Spotify", name: "Spotify", site: "spotify.com", desc: "Music and podcasts." },
        { id: "Audacity.Audacity", name: "Audacity", site: "audacityteam.org", desc: "Record and edit audio." },
        { id: "HandBrake.HandBrake", name: "HandBrake", site: "handbrake.fr", desc: "Convert videos between formats." },
        { id: "BlenderFoundation.Blender", name: "Blender", site: "blender.org", desc: "3D, animation and video editing." },
        { id: "GIMP.GIMP.3", name: "GIMP", site: "gimp.org", desc: "Edit images, free." },
        { id: "Inkscape.Inkscape", name: "Inkscape", site: "inkscape.org", desc: "Vector graphics." },
        { id: "KDE.Krita", name: "Krita", site: "krita.org", desc: "Digital painting." },
        { id: "Figma.Figma", name: "Figma", site: "figma.com", desc: "Interface design." },
        { id: "ShareX.ShareX", name: "ShareX", site: "getsharex.com", desc: "Screenshots and screen recordings with sharing." }
    ] },
    { key: "games", icon: "sports_esports", name: "Games and chat", apps: [
        { id: "Valve.Steam", name: "Steam", site: "steampowered.com", desc: "The biggest PC game store." },
        { id: "EpicGames.EpicGamesLauncher", name: "Epic Games Launcher", site: "epicgames.com", desc: "Epic's store and free games." },
        { id: "Playnite.Playnite", name: "Playnite", site: "playnite.link", desc: "All your game libraries in one place." },
        { id: "Discord.Discord", name: "Discord", site: "discord.com", desc: "Voice, video and text with friends." },
        { id: "Telegram.TelegramDesktop", name: "Telegram", aka: ["Telegram Desktop"], site: "telegram.org", desc: "Fast messaging." },
        { id: "Zoom.Zoom", name: "Zoom", aka: ["Zoom Workplace"], site: "zoom.us", desc: "Video calls." }
    ] },
    { key: "tools", icon: "build", name: "Tools", apps: [
        { id: "7zip.7zip", name: "7-Zip", site: "7-zip.org", desc: "Open and create .7z, .zip, .rar and more." },
        { id: "voidtools.Everything", name: "Everything", site: "voidtools.com", desc: "Instant file search." },
        { id: "Obsidian.Obsidian", name: "Obsidian", site: "obsidian.md", desc: "Notes in Markdown, linked." },
        { id: "Bitwarden.Bitwarden", name: "Bitwarden", site: "bitwarden.com", desc: "Password manager." },
        { id: "qBittorrent.qBittorrent", name: "qBittorrent", site: "qbittorrent.org", desc: "Torrent client without ads." },
        { id: "LocalSend.LocalSend", name: "LocalSend", site: "localsend.org", desc: "Send files to nearby devices." },
        { id: "CPUID.HWMonitor", name: "HWMonitor", site: "cpuid.com", desc: "Temperatures and voltages." },
        { id: "Rufus.Rufus", name: "Rufus", site: "rufus.ie", desc: "Make bootable USB drives." },
        { id: "Balena.Etcher", name: "balenaEtcher", aka: ["Etcher"], site: "etcher.balena.io", desc: "Flash images to USB and SD cards." },
        { id: "SumatraPDF.SumatraPDF", name: "SumatraPDF", site: "sumatrapdfreader.org", desc: "Light PDF reader." },
        { id: "AutoHotkey.AutoHotkey", name: "AutoHotkey", site: "autohotkey.com", desc: "Automate keys and clicks with scripts." },
        { id: "WinDirStat.WinDirStat", name: "WinDirStat", site: "windirstat.net", desc: "See what is using your disk." },
        { id: "Microsoft.Sysinternals.ProcessExplorer", name: "Process Explorer", aka: ["Sysinternals Process Explorer"], site: "learn.microsoft.com", desc: "A Task Manager with the details." }
    ] }
];

// What the home page shows: the first apps of every category.
function featured() {
    var list = [];
    for (var c = 0; c < categories.length; c++)
        for (var a = 0; a < Math.min(3, categories[c].apps.length); a++)
            list.push(categories[c].apps[a]);
    return list;
}

function byId(id) {
    var lower = String(id).toLowerCase();
    for (var c = 0; c < categories.length; c++)
        for (var a = 0; a < categories[c].apps.length; a++)
            if (categories[c].apps[a].id.toLowerCase() === lower) return categories[c].apps[a];
    return null;
}

// The front page carousel: a few apps with a line that sells them.
var heroPicks = [
    { id: "Microsoft.VisualStudioCode", tagline: "Code with superpowers: extensions for every language." },
    { id: "Spotify.Spotify", tagline: "Your music and podcasts, and the lyrics on ii's desktop." },
    { id: "Valve.Steam", tagline: "Thousands of games, sales every week." },
    { id: "OBSProject.OBSStudio", tagline: "Record and stream your screen like a pro." },
    { id: "Obsidian.Obsidian", tagline: "A second brain in plain Markdown files." },
    { id: "Discord.Discord", tagline: "Where your friends and communities hang out." }
];

function heroes() {
    var list = [];
    for (var i = 0; i < heroPicks.length; i++) {
        var app = byId(heroPicks[i].id);
        if (!app) continue;
        var copy = {};
        for (var k in app) copy[k] = app[k];
        copy.tagline = heroPicks[i].tagline;
        list.push(copy);
    }
    return list;
}
