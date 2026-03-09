# listing.nu -- Icon lookup for file listings
# Maps file extensions, well-known names, and directory names to Nerd Font glyphs
# Ported from Terminal-Icons devblackops.psd1

# Extension icons (extension without leading dot as key)
const EXT_ICONS = {
    # Archives
    "7z": "\u{f410}"
    bz: "\u{f410}"
    tar: "\u{f410}"
    zip: "\u{f410}"
    gz: "\u{f410}"
    xz: "\u{f410}"
    br: "\u{f410}"
    bzip2: "\u{f410}"
    gzip: "\u{f410}"
    brotli: "\u{f410}"
    rar: "\u{f410}"
    tgz: "\u{f410}"
    # Executables
    bat: "\u{e629}"
    cmd: "\u{e629}"
    exe: "\u{fb13}"
    pl: "\u{e769}"
    sh: "\u{f489}"
    # App packages
    msi: "\u{f8d5}"
    msix: "\u{f8d5}"
    msixbundle: "\u{f8d5}"
    appx: "\u{f8d5}"
    AppxBundle: "\u{f8d5}"
    deb: "\u{f8d5}"
    rpm: "\u{f8d5}"
    # PowerShell
    ps1: "\u{fcb5}"
    psm1: "\u{fcb5}"
    psd1: "\u{fcb5}"
    ps1xml: "\u{fcb5}"
    psc1: "\u{fcb5}"
    pssc: "\u{fcb5}"
    # JavaScript
    js: "\u{e74e}"
    esx: "\u{e74e}"
    mjs: "\u{e74e}"
    # Java
    java: "\u{e256}"
    jar: "\u{e256}"
    gradle: "\u{fcc4}"
    # Python
    py: "\u{e73c}"
    ipynb: "\u{fd2c}"
    # React
    jsx: "\u{e7ba}"
    tsx: "\u{e7ba}"
    # TypeScript
    ts: "\u{e628}"
    # Binary
    dll: "\u{f187}"
    # Data files
    clixml: "\u{e7a3}"
    csv: "\u{f71a}"
    tsv: "\u{f71a}"
    # Settings
    ini: "\u{f013}"
    dlc: "\u{f013}"
    config: "\u{f013}"
    conf: "\u{f013}"
    properties: "\u{f013}"
    prop: "\u{f013}"
    settings: "\u{f013}"
    option: "\u{f013}"
    reg: "\u{f013}"
    props: "\u{f013}"
    toml: "\u{f013}"
    prefs: "\u{f013}"
    cfg: "\u{f013}"
    # Source files
    c: "\u{fb70}"
    cpp: "\u{fb71}"
    go: "\u{e724}"
    php: "\u{e73d}"
    scala: "\u{e737}"
    # Visual Studio
    csproj: "\u{e70c}"
    ruleset: "\u{e70c}"
    sln: "\u{e70c}"
    slnf: "\u{e70c}"
    suo: "\u{e70c}"
    vb: "\u{e70c}"
    vbs: "\u{e70c}"
    vcxitems: "\u{e70c}"
    vcxproj: "\u{e70c}"
    # C#
    cs: "\u{f81a}"
    csx: "\u{f81a}"
    # Haskell
    hs: "\u{e777}"
    # XAML
    xaml: "\u{fb72}"
    # Rust
    rs: "\u{e7a8}"
    # Database
    pdb: "\u{e706}"
    sql: "\u{e706}"
    pks: "\u{e706}"
    pkb: "\u{e706}"
    accdb: "\u{e706}"
    mdb: "\u{e706}"
    sqlite: "\u{e706}"
    pgsql: "\u{e706}"
    postgres: "\u{e706}"
    psql: "\u{e706}"
    # Source control
    patch: "\u{e702}"
    # Project files
    user: "\u{e70c}"
    code-workspace: "\u{e70c}"
    # Text
    log: "\u{f03a}"
    txt: "\u{f718}"
    # Subtitles
    srt: "\u{f718}"
    lrc: "\u{f718}"
    ass: "\u{f06e}"
    # HTML/CSS
    html: "\u{e60e}"
    htm: "\u{e60e}"
    xhtml: "\u{e60e}"
    html_vm: "\u{e60e}"
    asp: "\u{e60e}"
    css: "\u{e749}"
    sass: "\u{e74b}"
    scss: "\u{e74b}"
    less: "\u{e758}"
    # Markdown
    md: "\u{e73e}"
    markdown: "\u{e73e}"
    rst: "\u{e73e}"
    # Handlebars
    hbs: "\u{e60f}"
    # JSON
    json: "\u{e60b}"
    tsbuildinfo: "\u{e60b}"
    # YAML
    yml: "\u{f761}"
    yaml: "\u{f761}"
    # Lua
    lua: "\u{e620}"
    # Clojure
    clj: "\u{e768}"
    cljs: "\u{e768}"
    cljc: "\u{e768}"
    # Groovy
    groovy: "\u{e775}"
    # Vue
    vue: "\u{fd42}"
    # Dart
    dart: "\u{e798}"
    # Elixir
    ex: "\u{e62d}"
    exs: "\u{e62d}"
    eex: "\u{e62d}"
    leex: "\u{e62d}"
    # Erlang
    erl: "\u{e7b1}"
    # Elm
    elm: "\u{e62c}"
    # AppleScript
    applescript: "\u{e711}"
    # XML
    xml: "\u{f72d}"
    plist: "\u{f72d}"
    xsd: "\u{f72d}"
    dtd: "\u{f72d}"
    xsl: "\u{f72d}"
    xslt: "\u{f72d}"
    resx: "\u{f72d}"
    iml: "\u{f72d}"
    xquery: "\u{f72d}"
    tmLanguage: "\u{f72d}"
    manifest: "\u{f72d}"
    project: "\u{f72d}"
    # Documents
    chm: "\u{fc89}"
    pdf: "\u{f724}"
    # Excel
    xls: "\u{f71a}"
    xlsx: "\u{f71a}"
    # PowerPoint
    pptx: "\u{f726}"
    ppt: "\u{f726}"
    pptm: "\u{f726}"
    potx: "\u{f726}"
    potm: "\u{f726}"
    ppsx: "\u{f726}"
    ppsm: "\u{f726}"
    pps: "\u{f726}"
    ppam: "\u{f726}"
    ppa: "\u{f726}"
    # Word
    doc: "\u{f72b}"
    docx: "\u{f72b}"
    rtf: "\u{f72b}"
    # Audio
    mp3: "\u{f1c7}"
    flac: "\u{f1c7}"
    m4a: "\u{f1c7}"
    wma: "\u{f1c7}"
    aiff: "\u{f1c7}"
    wav: "\u{f1c7}"
    aac: "\u{f1c7}"
    opus: "\u{f1c7}"
    # Images
    png: "\u{f1c5}"
    jpeg: "\u{f1c5}"
    jpg: "\u{f1c5}"
    gif: "\u{f1c5}"
    ico: "\u{f1c5}"
    tif: "\u{f1c5}"
    tiff: "\u{f1c5}"
    psd: "\u{f1c5}"
    psb: "\u{f1c5}"
    ami: "\u{f1c5}"
    apx: "\u{f1c5}"
    bmp: "\u{f1c5}"
    bpg: "\u{f1c5}"
    brk: "\u{f1c5}"
    cur: "\u{f1c5}"
    dds: "\u{f1c5}"
    dng: "\u{f1c5}"
    eps: "\u{f1c5}"
    exr: "\u{f1c5}"
    fpx: "\u{f1c5}"
    gbr: "\u{f1c5}"
    jbig2: "\u{f1c5}"
    jb2: "\u{f1c5}"
    jng: "\u{f1c5}"
    jxr: "\u{f1c5}"
    pbm: "\u{f1c5}"
    pgf: "\u{f1c5}"
    pic: "\u{f1c5}"
    raw: "\u{f1c5}"
    webp: "\u{f1c5}"
    svg: "\u{fc1f}"
    # Video
    webm: "\u{f1c8}"
    mkv: "\u{f1c8}"
    flv: "\u{f1c8}"
    vob: "\u{f1c8}"
    ogv: "\u{f1c8}"
    ogg: "\u{f1c8}"
    gifv: "\u{f1c8}"
    avi: "\u{f1c8}"
    mov: "\u{f1c8}"
    qt: "\u{f1c8}"
    wmv: "\u{f1c8}"
    yuv: "\u{f1c8}"
    rm: "\u{f1c8}"
    rmvb: "\u{f1c8}"
    mp4: "\u{f1c8}"
    mpg: "\u{f1c8}"
    mp2: "\u{f1c8}"
    mpeg: "\u{f1c8}"
    mpe: "\u{f1c8}"
    mpv: "\u{f1c8}"
    m2v: "\u{f1c8}"
    # Calendar
    ics: "\u{f073}"
    # Certificates
    cer: "\u{f0a3}"
    cert: "\u{f0a3}"
    crt: "\u{f0a3}"
    pfx: "\u{f0a3}"
    # Keys
    pem: "\u{f084}"
    pub: "\u{f084}"
    key: "\u{f084}"
    asc: "\u{f084}"
    gpg: "\u{f084}"
    # Fonts
    woff: "\u{f031}"
    woff2: "\u{f031}"
    ttf: "\u{f031}"
    eot: "\u{f031}"
    suit: "\u{f031}"
    otf: "\u{f031}"
    bmap: "\u{f031}"
    fnt: "\u{f031}"
    odttf: "\u{f031}"
    ttc: "\u{f031}"
    font: "\u{f031}"
    fonts: "\u{f031}"
    sui: "\u{f031}"
    ntf: "\u{f031}"
    mrg: "\u{f031}"
    # Ruby
    rb: "\u{f43b}"
    erb: "\u{f43b}"
    gemfile: "\u{f43b}"
    # F#
    fs: "\u{e7a7}"
    fsx: "\u{e7a7}"
    fsi: "\u{e7a7}"
    fsproj: "\u{e7a7}"
    # Docker
    dockerignore: "\u{e7b0}"
    dockerfile: "\u{e7b0}"
    # VSCode
    vscodeignore: "\u{f013}"
    vsixmanifest: "\u{f013}"
    vsix: "\u{f013}"
    code-workplace: "\u{f013}"
    # Sublime
    sublime-project: "\u{e7aa}"
    sublime-workspace: "\u{e7aa}"
    # Lock
    lock: "\u{f023}"
    # Terraform
    tf: "\u{e7a3}"
    tfvars: "\u{e7a3}"
    # Disk images
    vmdk: "\u{f7c9}"
    vhd: "\u{f7c9}"
    vhdx: "\u{f7c9}"
    img: "\u{e271}"
    iso: "\u{e271}"
    # R
    R: "\u{fcd2}"
    Rmd: "\u{fcd2}"
    Rproj: "\u{fcd2}"
    # Julia
    jl: "\u{e624}"
    # Vim
    vim: "\u{e62b}"
    # Unity
    asset: "\u{e706}"
    unity: "\u{e706}"
    meta: "\u{f013}"
    lighting: "\u{e706}"
    # Nushell
    nu: "\u{f489}"
}

# Get icon for a directory by name
def get-dir-icon [name: string] : string -> string {
    match $name {
        "docs" | "documents" => "\u{f401}"
        "desktop" => "\u{fcbe}"
        "contacts" => "\u{fbc9}"
        "apps" | "applications" => "\u{f53a}"
        "shortcuts" | "links" => "\u{f482}"
        "fonts" => "\u{f031}"
        "images" | "photos" | "pictures" => "\u{f74e}"
        "videos" | "movies" => "\u{f880}"
        "media" => "\u{e732}"
        "music" | "songs" => "\u{f832}"
        "onedrive" => "\u{f8c9}"
        "downloads" => "\u{f74c}"
        "src" | "development" => "\u{f489}"
        "projects" => "\u{e601}"
        "bin" => "\u{f471}"
        "tests" => "\u{fb67}"
        "windows" => "\u{f17a}"
        "users" => "\u{f0c0}"
        "favorites" => "\u{fb9b}"
        ".config" => "\u{e615}"
        ".cache" => "\u{f5e7}"
        ".vscode" | ".vscode-insiders" => "\u{e5fc}"
        ".git" => "\u{e5fb}"
        ".github" => "\u{e5fd}"
        "github" => "\u{f113}"
        "node_modules" => "\u{e5fa}"
        ".terraform" => "\u{e7a3}"
        ".azure" => "\u{fd03}"
        ".aws" => "\u{e7ad}"
        ".kube" => "\u{fd31}"
        ".docker" => "\u{e7b0}"
        _ => "\u{f413}"
    }
}

# Get icon for well-known filenames (exact match)
def get-wellknown-icon [name: string] : string -> any {
    match $name {
        ".gitattributes" | ".gitconfig" | ".gitignore" | ".gitmodules" | ".gitkeep" | "git-history" => "\u{e702}"
        "LICENSE" | "LICENSE.md" | "LICENSE.txt" => "\u{f623}"
        "CHANGELOG.md" | "CHANGELOG.txt" | "CHANGELOG" => "\u{e29a}"
        "README.md" | "README.txt" | "README" => "\u{f831}"
        ".DS_Store" => "\u{f016}"
        ".tsbuildinfo" | ".jscsrc" | ".jshintrc" | "tsconfig.json" | "tslint.json"
            | "composer.lock" | ".jsbeautifyrc" | ".esformatter" | "cdp.pid" => "\u{e60b}"
        ".htaccess" => "\u{f72d}"
        ".jshintignore" | ".buildignore" | ".mrconfig" | ".yardopts"
            | "manifest.mf" | ".clang-format" | ".clang-tidy" => "\u{f013}"
        "favicon.ico" => "\u{e623}"
        ".travis.yml" => "\u{e77e}"
        ".gitlab-ci.yml" => "\u{f296}"
        ".jenkinsfile" => "\u{e767}"
        "bitbucket-pipelines.yml" | "bitbucket-pipelines.yaml" => "\u{e703}"
        ".azure-pipelines.yml" => "\u{fd03}"
        "firebase.json" | ".firebaserc" => "\u{e787}"
        ".bowerrc" | "bower.json" => "\u{e74d}"
        "code_of_conduct.md" | "code_of_conduct.txt" => "\u{f2b5}"
        "Dockerfile" | "docker-compose.yml" | "docker-compose.yaml"
            | "docker-compose.dev.yml" | "docker-compose.local.yml"
            | "docker-compose.ci.yml" | "docker-compose.override.yml"
            | "docker-compose.staging.yml" | "docker-compose.prod.yml"
            | "docker-compose.production.yml" | "docker-compose.test.yml" => "\u{e7b0}"
        "vue.config.js" | "vue.config.ts" => "\u{fd42}"
        "gulpfile.js" | "gulpfile.ts" | "gulpfile.babel.js" => "\u{e763}"
        "gruntfile.js" => "\u{e611}"
        "package.json" | "package-lock.json" | ".nvmrc" | ".esmrc" => "\u{e718}"
        ".npmignore" | ".npmrc" => "\u{e71e}"
        "authors" | "authors.md" | "authors.txt" => "\u{f415}"
        ".terraform.lock.hcl" => "\u{f023}"
        "gradlew" => "\u{fcc4}"
        _ => null
    }
}

# Main icon lookup function
# Returns a Nerd Font glyph for the given filename and type
def get-file-icon [name: string, file_type: string] : string -> string {
    let basename = ($name | path basename)

    # Directory icons
    if $file_type == "dir" {
        return (get-dir-icon $basename)
    }

    # Symlink icon
    if $file_type == "symlink" {
        return "\u{f481}"
    }

    # Check well-known filenames
    let wk = (get-wellknown-icon $basename)
    if $wk != null {
        return $wk
    }

    # Check by extension
    let ext = ($name | path parse | get extension)
    if $ext != "" {
        let ext_icon = ($EXT_ICONS | get? $ext)
        if $ext_icon != null {
            return $ext_icon
        }
    }

    # Default file icon
    "\u{f016}"
}

# Color lookup from LS_COLORS (via _LS_COLOR_MAP built in env.nu)
# Returns an ANSI escape sequence string, or empty string if no match
def get-file-color [name: string, file_type: string] : string -> string {
    let colors = $env._LS_COLOR_MAP

    if $file_type == "dir" {
        let code = ($colors | get? di | default "")
        if $code != "" { return $"\u{1b}[($code)m" }
        return ""
    }

    if $file_type == "symlink" {
        let code = ($colors | get? ln | default "")
        if $code != "" { return $"\u{1b}[($code)m" }
        return ""
    }

    let ext = ($name | path parse | get extension)
    if $ext != "" {
        let code = ($colors | get? $ext | default "")
        if $code != "" { return $"\u{1b}[($code)m" }
    }

    ""
}

# Format a file entry with icon, color, and type suffix (/ for dirs, @ for symlinks)
def format-file-entry [name: string, file_type: string] : string -> string {
    let icon = (get-file-icon $name $file_type)
    let color = (get-file-color $name $file_type)
    let suffix = (match $file_type {
        "dir" => "/"
        "symlink" => "@"
        _ => ""
    })
    let basename = ($name | path basename)
    if $color != "" {
        $"($color)($icon) ($basename)($suffix)(ansi reset)"
    } else {
        $"($icon) ($basename)($suffix)"
    }
}
