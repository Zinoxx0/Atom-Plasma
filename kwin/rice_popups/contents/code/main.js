/*
    Rice popups (plasma-rice): KWin's Fading popups with the rice's motion tokens.
    Menus, tooltips and dropdowns fade in while sliding a few px away from where they were opened
    (down for a menu under the pointer, up for a tooltip over the bar); everything else Fading popups
    handled (applet popups, OSDs, splash, outline) only fades, as before. Closing is a quick fade.

    Based on fadingpopups/main.js:
    SPDX-FileCopyrightText: 2018 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

"use strict";

var blacklist = [
    // ignore black background behind lockscreen
    "ksmserver ksmserver",
    // The logout screen has to be animated only by the logout effect.
    "ksmserver-logout-greeter ksmserver-logout-greeter",
    // The lockscreen isn't a popup window
    "kscreenlocker_greet kscreenlocker_greet",
    // KDE Plasma splash screen has to be animated only by the login effect.
    "ksplashqml ksplashqml",
];

function isPopupWindow(window) {
    if (blacklist.indexOf(window.windowClass) != -1) {
        return false;
    }

    // Combo box popups, tooltips, popup menus, etc.
    if (window.popupWindow) {
        return true;
    }

    if (window.outline) {
        return true;
    }

    // Override-redirect windows are usually popups too (e.g. X11 window thumbnails),
    // except utility windows that only look like popups (Firefox's address bar dropdown).
    if (!window.managed) {
        return !window.utility;
    }

    if (window.splash || window.toolbar || window.onScreenDisplay || window.appletPopup) {
        return true;
    }

    return false;
}

var ricePopups = {
    loadConfig: function () {
        ricePopups.inDuration = animationTime(effect.readConfig("InDuration", 150) || 150);
        ricePopups.outDuration = animationTime(effect.readConfig("OutDuration", 120) || 120);
        ricePopups.slide = effect.readConfig("Slide", 4);
    },
    // vertical offset to slide in from. Effects don't see the pointer, so guess where the popup came
    // from by where it sits: in the lower half of its screen it most likely opened upwards (tooltips
    // over the bar, menus near the bottom) and rises into place; otherwise it drops into place.
    slideFrom: function (window) {
        if (!window.popupWindow || !ricePopups.slide) {
            return 0;
        }
        try {
            var g = window.frameGeometry, s = window.screen.geometry;
            return g.y + g.height / 2 > s.y + s.height / 2 ? ricePopups.slide : -ricePopups.slide;
        } catch (e) {
            return 0;   // never lose the fade over the slide
        }
    },
    slotWindowAdded: function (window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (!isPopupWindow(window)) {
            return;
        }
        if (!window.visible) {
            return;
        }
        if (!effect.grab(window, Effect.WindowAddedGrabRole)) {
            return;
        }
        var animations = [{ type: Effect.Opacity, from: 0.0, to: 1.0 }];
        var dy = ricePopups.slideFrom(window);
        if (dy) {
            animations.push({
                type: Effect.Translation,
                from: { value1: 0.0, value2: dy },
                to: { value1: 0.0, value2: 0.0 }
            });
        }
        window.riceFadeInAnimation = animate({
            window: window,
            curve: QEasingCurve.OutCubic,
            duration: ricePopups.inDuration,
            animations: animations
        });
    },
    slotWindowClosed: function (window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (!isPopupWindow(window)) {
            return;
        }
        if (!window.visible || window.skipsCloseAnimation) {
            return;
        }
        if (!effect.grab(window, Effect.WindowClosedGrabRole)) {
            return;
        }
        window.riceFadeOutAnimation = animate({
            window: window,
            curve: QEasingCurve.InCubic,
            duration: ricePopups.outDuration,
            type: Effect.Opacity,
            from: 1.0,
            to: 0.0
        });
    },
    slotWindowDataChanged: function (window, role) {
        if (role == Effect.WindowAddedGrabRole) {
            if (window.riceFadeInAnimation && effect.isGrabbed(window, role)) {
                cancel(window.riceFadeInAnimation);
                delete window.riceFadeInAnimation;
            }
        } else if (role == Effect.WindowClosedGrabRole) {
            if (window.riceFadeOutAnimation && effect.isGrabbed(window, role)) {
                cancel(window.riceFadeOutAnimation);
                delete window.riceFadeOutAnimation;
            }
        }
    },
    init: function () {
        ricePopups.loadConfig();

        effect.configChanged.connect(ricePopups.loadConfig);
        effects.windowAdded.connect(ricePopups.slotWindowAdded);
        effects.windowClosed.connect(ricePopups.slotWindowClosed);
        effects.windowDataChanged.connect(ricePopups.slotWindowDataChanged);
    }
};

ricePopups.init();
