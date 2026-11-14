# Sourced by the bar tests: bar_applets SCREEN PANEL DESK WALL PINS prints one screen's rice bar (panel.TEMPLATE's
# order, applet ids PANEL*20+2..) and its desktop (wallpaper WALL; set it again by script after start, Plasma
# keys it by activity), for an appletsrc.
bar_applets() {
    local scr=$1 c=$2 d=$3 wall=$4 pins=$5 n=$(( $2 * 20 + 2 )) first=$(( $2 * 20 + 2 )) ids=""
    printf '[Containments][%s]\nactivityId=\nformfactor=2\nimmutability=1\nlastScreen=%s\nlocation=4\nplugin=org.kde.panel\nwallpaperplugin=org.kde.image\n\n' $c $scr
    printf '[Containments][%s]\nactivityId=\nformfactor=0\nimmutability=1\nlastScreen=%s\nlocation=0\nplugin=org.kde.plasma.folder\nwallpaperplugin=org.kde.image\n\n' $d $scr
    printf '[Containments][%s][Wallpaper][org.kde.image][General]\nImage=file://%s\n\n' $d "$wall"
    for p in com.zinoxx.launcher S com.zinoxx.glimpse E com.zinoxx.shell luisbocanegra.panel.colorizer S \
             com.zinoxx.claudeusage com.zinoxx.sysstats S com.zinoxx.status com.zinoxx.tiling com.zinoxx.session S com.zinoxx.clock; do
        case $p in
            S) printf '[Containments][%s][Applets][%s]\nimmutability=1\nplugin=org.kde.plasma.panelspacer\n\n[Containments][%s][Applets][%s][Configuration][General]\nexpanding=false\nlength=4\n\n' $c $n $c $n ;;
            E) printf '[Containments][%s][Applets][%s]\nimmutability=1\nplugin=org.kde.plasma.panelspacer\n\n[Containments][%s][Applets][%s][Configuration][General]\nexpanding=true\n\n' $c $n $c $n ;;
            com.zinoxx.glimpse) printf '[Containments][%s][Applets][%s]\nimmutability=1\nplugin=%s\n\n[Containments][%s][Applets][%s][Configuration][General]\nlaunchers=%s\n\n' $c $n $p $c $n "$pins" ;;
            *) printf '[Containments][%s][Applets][%s]\nimmutability=1\nplugin=%s\n\n' $c $n "$p" ;;
        esac
        ids="$ids${ids:+;}$n"; n=$((n + 1))
    done
    printf '[Containments][%s][General]\nAppletOrder=%s\n\n' $c "$ids"
}
