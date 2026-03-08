# let's define some colors

let base00 = "#181818" # Default Background
let base01 = "#282828" # Lighter Background (Used for status bars, line number and folding marks)
let base02 = "#383838" # Selection Background
let base03 = "#585858" # Comments, Invisibles, Line Highlighting
let base04 = "#b8b8b8" # Dark Foreground (Used for status bars)
let base05 = "#d8d8d8" # Default Foreground, Caret, Delimiters, Operators
let base06 = "#e8e8e8" # Light Foreground (Not often used)
let base07 = "#f8f8f8" # Light Background (Not often used)
let base08 = "#ab4642" # Variables, XML Tags, Markup Link Text, Markup Lists, Diff Deleted
let base09 = "#dc9656" # Integers, Boolean, Constants, XML Attributes, Markup Link Url
let base0a = "#f7ca88" # Classes, Markup Bold, Search Text Background
let base0b = "#a1b56c" # Strings, Inherited Class, Markup Code, Diff Inserted
let base0c = "#86c1b9" # Support, Regular Expressions, Escape Characters, Markup Quotes
let base0d = "#7cafc2" # Functions, Methods, Attribute IDs, Headings
let base0e = "#ba8baf" # Keywords, Storage, Selector, Markup Italic, Diff Changed
let base0f = "#a16946" # Deprecated, Opening/Closing Embedded Language Tags, e.g. <?php ?>

# we're creating a theme here that uses the colors we defined above.

let base16_theme = {
    separator: $base03
    leading_trailing_space_bg: $base04
    header: $base0b
    datetime: $base0e
    filesize: $base0d
    row_index: $base0c
    bool: $base08
    int: $base0b
    duration: $base08
    range: $base08
    float: $base08
    string: $base04
    nothing: $base08
    binary: $base08
    cell-path: $base08
    hints: dark_gray

    # shape_garbage: { fg: $base07 bg: $base08 attr: b } # base16 white on red
    # but i like the regular white on red for parse errors
    shape_garbage: { fg: "#FFFFFF" bg: "#FF0000" attr: b }
    shape_bool: $base0d
    shape_int: { fg: $base0e attr: b }
    shape_float: { fg: $base0e attr: b }
    shape_range: { fg: $base0a attr: b }
    shape_internalcall: { fg: $base0c attr: b }
    shape_external: $base0c
    shape_externalarg: { fg: $base0b attr: b }
    shape_literal: $base0d
    shape_operator: $base0a
    shape_signature: { fg: $base0b attr: b }
    shape_string: $base0b
    shape_filepath: $base0d
    shape_globpattern: { fg: $base0d attr: b }
    shape_variable: $base0e
    shape_flag: { fg: $base0d attr: b }
    shape_custom: { attr: b }
}

# and some fun with other colors
# LS_COLORS -- generated from ddriver.theme.psd1
# Format: 38;2;R;G;B for truecolor (24-bit) ANSI
$env.LS_COLORS = ([
    # Directories and symlinks
    "di=38;2;186;90;219"
    "ln=38;2;115;115;255"
    # Well-known files
    "README.md=38;2;0;255;255"
    "README.txt=38;2;0;255;255"
    "README=38;2;0;255;255"
    "LICENSE=38;2;205;92;92"
    "LICENSE.md=38;2;205;92;92"
    "LICENSE.txt=38;2;205;92;92"
    "CHANGELOG.md=38;2;152;251;152"
    "CHANGELOG.txt=38;2;152;251;152"
    "CHANGELOG=38;2;152;251;152"
    "Dockerfile=38;2;70;130;180"
    "Makefile=38;2;107;142;35"
    # Archives
    "*.7z=38;2;218;165;32"
    "*.bz=38;2;218;165;32"
    "*.tar=38;2;218;165;32"
    "*.zip=38;2;218;165;32"
    "*.gz=38;2;218;165;32"
    "*.xz=38;2;218;165;32"
    "*.br=38;2;218;165;32"
    "*.bzip2=38;2;218;165;32"
    "*.gzip=38;2;218;165;32"
    "*.brotli=38;2;218;165;32"
    "*.rar=38;2;218;165;32"
    "*.tgz=38;2;218;165;32"
    # Executables
    "*.bat=38;2;0;128;0"
    "*.cmd=38;2;0;128;0"
    "*.exe=38;2;0;250;154"
    "*.pl=38;2;138;43;226"
    "*.sh=38;2;255;69;0"
    # App packages
    "*.msi=38;2;255;199;122"
    "*.msix=38;2;255;199;122"
    "*.msixbundle=38;2;255;199;122"
    "*.appx=38;2;255;199;122"
    "*.AppxBundle=38;2;255;199;122"
    "*.deb=38;2;255;199;122"
    "*.rpm=38;2;255;199;122"
    # PowerShell
    "*.ps1=38;2;0;191;255"
    "*.psm1=38;2;0;191;255"
    "*.psd1=38;2;0;191;255"
    "*.ps1xml=38;2;0;191;255"
    "*.psc1=38;2;0;191;255"
    "*.pssc=38;2;0;191;255"
    # JavaScript
    "*.js=38;2;240;230;140"
    "*.esx=38;2;240;230;140"
    "*.mjs=38;2;240;230;140"
    # Java
    "*.java=38;2;248;152;32"
    "*.jar=38;2;248;152;32"
    "*.gradle=38;2;57;213;45"
    # Python
    "*.py=38;2;75;139;190"
    "*.ipynb=38;2;75;139;190"
    # React
    "*.jsx=38;2;32;178;170"
    "*.tsx=38;2;32;178;170"
    # TypeScript
    "*.ts=38;2;240;230;140"
    # Binary
    "*.dll=38;2;135;206;235"
    # Data files
    "*.clixml=38;2;0;191;255"
    "*.csv=38;2;154;205;50"
    "*.tsv=38;2;154;205;50"
    # Settings
    "*.ini=38;2;100;149;237"
    "*.dlc=38;2;100;149;237"
    "*.config=38;2;100;149;237"
    "*.conf=38;2;100;149;237"
    "*.properties=38;2;100;149;237"
    "*.prop=38;2;100;149;237"
    "*.settings=38;2;100;149;237"
    "*.option=38;2;100;149;237"
    "*.reg=38;2;100;149;237"
    "*.props=38;2;100;149;237"
    "*.toml=38;2;100;149;237"
    "*.prefs=38;2;100;149;237"
    "*.cfg=38;2;100;149;237"
    # Source files
    "*.c=38;2;32;178;170"
    "*.cpp=38;2;32;178;170"
    "*.go=38;2;32;178;170"
    "*.php=38;2;32;178;170"
    "*.scala=38;2;32;178;170"
    # Visual Studio
    "*.csproj=38;2;238;130;238"
    "*.ruleset=38;2;238;130;238"
    "*.sln=38;2;238;130;238"
    "*.slnf=38;2;238;130;238"
    "*.suo=38;2;238;130;238"
    "*.vb=38;2;238;130;238"
    "*.vbs=38;2;238;130;238"
    "*.vcxitems=38;2;238;130;238"
    "*.vcxproj=38;2;238;130;238"
    # C#
    "*.cs=38;2;123;104;238"
    "*.csx=38;2;123;104;238"
    # Haskell
    "*.hs=38;2;153;50;204"
    # XAML
    "*.xaml=38;2;135;206;250"
    # Rust
    "*.rs=38;2;255;69;0"
    # Database
    "*.pdb=38;2;255;215;0"
    "*.sql=38;2;255;215;0"
    "*.pks=38;2;255;215;0"
    "*.pkb=38;2;255;215;0"
    "*.accdb=38;2;255;215;0"
    "*.mdb=38;2;255;215;0"
    "*.sqlite=38;2;255;215;0"
    "*.pgsql=38;2;255;215;0"
    "*.postgres=38;2;255;215;0"
    "*.psql=38;2;255;215;0"
    # Source control
    "*.patch=38;2;255;69;0"
    # Project files
    "*.user=38;2;0;191;255"
    "*.code-workspace=38;2;0;191;255"
    # Text
    "*.log=38;2;240;230;140"
    "*.txt=38;2;0;206;209"
    # Subtitles
    "*.srt=38;2;0;206;209"
    "*.lrc=38;2;0;206;209"
    "*.ass=38;2;197;0;0"
    # HTML/CSS
    "*.html=38;2;205;92;92"
    "*.htm=38;2;205;92;92"
    "*.xhtml=38;2;205;92;92"
    "*.html_vm=38;2;205;92;92"
    "*.asp=38;2;205;92;92"
    "*.css=38;2;135;206;250"
    "*.sass=38;2;255;0;255"
    "*.scss=38;2;255;0;255"
    "*.less=38;2;107;142;35"
    # Markdown
    "*.md=38;2;0;191;255"
    "*.markdown=38;2;0;191;255"
    "*.rst=38;2;0;191;255"
    # Handlebars
    "*.hbs=38;2;227;121;51"
    # JSON
    "*.json=38;2;255;215;0"
    "*.tsbuildinfo=38;2;255;215;0"
    # YAML
    "*.yml=38;2;255;99;71"
    "*.yaml=38;2;255;99;71"
    # Lua
    "*.lua=38;2;135;206;250"
    # Clojure
    "*.clj=38;2;0;255;127"
    "*.cljs=38;2;0;255;127"
    "*.cljc=38;2;0;255;127"
    # Groovy
    "*.groovy=38;2;135;206;250"
    # Vue
    "*.vue=38;2;32;178;170"
    # Dart
    "*.dart=38;2;70;130;180"
    # Elixir
    "*.ex=38;2;139;69;19"
    "*.exs=38;2;139;69;19"
    "*.eex=38;2;139;69;19"
    "*.leex=38;2;139;69;19"
    # Erlang
    "*.erl=38;2;255;99;71"
    # Elm
    "*.elm=38;2;153;50;204"
    # AppleScript
    "*.applescript=38;2;70;130;180"
    # XML
    "*.xml=38;2;152;251;152"
    "*.plist=38;2;152;251;152"
    "*.xsd=38;2;152;251;152"
    "*.dtd=38;2;152;251;152"
    "*.xsl=38;2;152;251;152"
    "*.xslt=38;2;152;251;152"
    "*.resx=38;2;152;251;152"
    "*.iml=38;2;152;251;152"
    "*.xquery=38;2;152;251;152"
    "*.tmLanguage=38;2;152;251;152"
    "*.manifest=38;2;152;251;152"
    "*.project=38;2;152;251;152"
    # Documents
    "*.chm=38;2;135;206;235"
    "*.pdf=38;2;205;92;92"
    # Excel
    "*.xls=38;2;154;205;50"
    "*.xlsx=38;2;154;205;50"
    # PowerPoint
    "*.pptx=38;2;220;20;60"
    "*.ppt=38;2;220;20;60"
    "*.pptm=38;2;220;20;60"
    "*.potx=38;2;220;20;60"
    "*.potm=38;2;220;20;60"
    "*.ppsx=38;2;220;20;60"
    "*.ppsm=38;2;220;20;60"
    "*.pps=38;2;220;20;60"
    "*.ppam=38;2;220;20;60"
    "*.ppa=38;2;220;20;60"
    # Word
    "*.doc=38;2;0;191;255"
    "*.docx=38;2;0;191;255"
    "*.rtf=38;2;0;191;255"
    # Audio
    "*.mp3=38;2;219;112;147"
    "*.flac=38;2;219;112;147"
    "*.m4a=38;2;219;112;147"
    "*.wma=38;2;219;112;147"
    "*.aiff=38;2;219;112;147"
    "*.wav=38;2;219;112;147"
    "*.aac=38;2;219;112;147"
    "*.opus=38;2;219;112;147"
    # Images
    "*.png=38;2;32;178;170"
    "*.jpeg=38;2;32;178;170"
    "*.jpg=38;2;32;178;170"
    "*.gif=38;2;32;178;170"
    "*.ico=38;2;32;178;170"
    "*.tif=38;2;32;178;170"
    "*.tiff=38;2;32;178;170"
    "*.psd=38;2;32;178;170"
    "*.psb=38;2;32;178;170"
    "*.ami=38;2;32;178;170"
    "*.apx=38;2;32;178;170"
    "*.bmp=38;2;32;178;170"
    "*.bpg=38;2;32;178;170"
    "*.brk=38;2;32;178;170"
    "*.cur=38;2;32;178;170"
    "*.dds=38;2;32;178;170"
    "*.dng=38;2;32;178;170"
    "*.eps=38;2;32;178;170"
    "*.exr=38;2;32;178;170"
    "*.fpx=38;2;32;178;170"
    "*.gbr=38;2;32;178;170"
    "*.jbig2=38;2;32;178;170"
    "*.jb2=38;2;32;178;170"
    "*.jng=38;2;32;178;170"
    "*.jxr=38;2;32;178;170"
    "*.pbm=38;2;32;178;170"
    "*.pgf=38;2;32;178;170"
    "*.pic=38;2;32;178;170"
    "*.raw=38;2;32;178;170"
    "*.webp=38;2;32;178;170"
    "*.svg=38;2;244;164;96"
    # Video
    "*.webm=38;2;255;165;0"
    "*.mkv=38;2;255;165;0"
    "*.flv=38;2;255;165;0"
    "*.vob=38;2;255;165;0"
    "*.ogv=38;2;255;165;0"
    "*.ogg=38;2;255;165;0"
    "*.gifv=38;2;255;165;0"
    "*.avi=38;2;255;165;0"
    "*.mov=38;2;255;165;0"
    "*.qt=38;2;255;165;0"
    "*.wmv=38;2;255;165;0"
    "*.yuv=38;2;255;165;0"
    "*.rm=38;2;255;165;0"
    "*.rmvb=38;2;255;165;0"
    "*.mp4=38;2;255;165;0"
    "*.mpg=38;2;255;165;0"
    "*.mp2=38;2;255;165;0"
    "*.mpeg=38;2;255;165;0"
    "*.mpe=38;2;255;165;0"
    "*.mpv=38;2;255;165;0"
    "*.m2v=38;2;255;165;0"
    # Calendar
    "*.ics=38;2;0;206;209"
    # Certificates
    "*.cer=38;2;255;99;71"
    "*.cert=38;2;255;99;71"
    "*.crt=38;2;255;99;71"
    "*.pfx=38;2;255;99;71"
    # Keys
    "*.pem=38;2;102;205;170"
    "*.pub=38;2;102;205;170"
    "*.key=38;2;102;205;170"
    "*.asc=38;2;102;205;170"
    "*.gpg=38;2;102;205;170"
    # Fonts
    "*.woff=38;2;220;20;60"
    "*.woff2=38;2;220;20;60"
    "*.ttf=38;2;220;20;60"
    "*.eot=38;2;220;20;60"
    "*.suit=38;2;220;20;60"
    "*.otf=38;2;220;20;60"
    "*.bmap=38;2;220;20;60"
    "*.fnt=38;2;220;20;60"
    "*.odttf=38;2;220;20;60"
    "*.ttc=38;2;220;20;60"
    "*.font=38;2;220;20;60"
    "*.fonts=38;2;220;20;60"
    "*.sui=38;2;220;20;60"
    "*.ntf=38;2;220;20;60"
    "*.mrg=38;2;220;20;60"
    # Ruby
    "*.rb=38;2;255;0;0"
    "*.erb=38;2;255;0;0"
    "*.gemfile=38;2;255;0;0"
    # F#
    "*.fs=38;2;0;191;255"
    "*.fsx=38;2;0;191;255"
    "*.fsi=38;2;0;191;255"
    "*.fsproj=38;2;0;191;255"
    # Docker
    "*.dockerignore=38;2;70;130;180"
    "*.dockerfile=38;2;70;130;180"
    # VSCode
    "*.vscodeignore=38;2;100;149;237"
    "*.vsixmanifest=38;2;100;149;237"
    "*.vsix=38;2;100;149;237"
    # Lock
    "*.lock=38;2;218;165;32"
    # Terraform
    "*.tf=38;2;148;142;236"
    "*.tfvars=38;2;148;142;236"
    # Disk images
    "*.vmdk=38;2;225;227;230"
    "*.vhd=38;2;225;227;230"
    "*.vhdx=38;2;225;227;230"
    "*.img=38;2;225;227;230"
    "*.iso=38;2;225;227;230"
    # R
    "*.R=38;2;39;109;195"
    "*.Rmd=38;2;39;109;195"
    "*.Rproj=38;2;39;109;195"
    # Julia
    "*.jl=38;2;146;89;163"
    # Vim
    "*.vim=38;2;1;152;51"
    # Unity
    "*.asset=38;2;162;103;235"
    "*.unity=38;2;162;103;235"
    "*.meta=38;2;128;128;128"
    "*.lighting=38;2;162;103;235"
    # Nushell
    "*.nu=38;2;0;191;255"
] | str join ":")

# EZA_COLORS -- only colorize filenames; reset all chrome (permissions, size, user, date)
# eza reads LS_COLORS for file extension colors; EZA_COLORS overrides chrome fields
$env.EZA_COLORS = ([
    # Permissions
    "ur=0" "uw=0" "ux=0" "ue=0"
    "gr=0" "gw=0" "gx=0"
    "tr=0" "tw=0" "tx=0"
    "su=0" "sf=0" "xa=0"
    # File size
    "sn=0" "sb=0" "df=0" "ds=0"
    # User / group
    "uu=0" "uR=0" "un=0"
    "gu=0" "gR=0" "gn=0"
    # Date
    "da=0"
    # Punctuation, header, link path
    "xx=0" "hd=0" "lp=0" "lc=0" "cc=0"
    # Filesize units
    "nb=0" "nk=0" "nm=0" "ng=0" "nt=0"
    # Blocks / inode
    "bO=0" "in=0" "mp=0"
] | str join ":")

# Build color lookup record from LS_COLORS for the display_output hook
# Keys: "di", "ln" for types; bare extension like "py", "js" for files
$env._LS_COLOR_MAP = ($env.LS_COLORS | split row ":"
    | each {|entry|
        let parts = ($entry | split row "=")
        let key = ($parts.0 | str replace "*." "")
        {($key): $parts.1}
    }
    | reduce -f {} {|it, acc| $acc | merge $it})


# now let's apply our regular config settings but also apply the "color_config:" theme that we specified above.

$env.config.color_config = $base16_theme # <-- this is the theme
