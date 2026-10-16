/*
    Rice window motion (plasma-rice): KWin's Scale effect with the rice's motion tokens.
    Open: fade in from 96 % size, OutCubic. Close: fade out to 98 %, InCubic, a little quicker.
    Small scales on purpose: the user chose "smooth and subtle" over glide/zoom effects.

    Based on scale/main.js:
    SPDX-FileCopyrightText: 2018, 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

"use strict";

const blacklist = {
    // The logout screen has to be animated only by the logout effect.
    "ksmserver ksmserver": [],
    "ksmserver-logout-greeter ksmserver-logout-greeter": [],

    // KDE Plasma splash screen has to be animated only by the login effect.
    "ksplashqml ksplashqml": [],

    "spectacle org.kde.spectacle": ["region-editor"],
};

class RiceWindowEffect {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.cleanupForcedRoles.bind(this));
        effects.windowAdded.connect(this.slotWindowAdded.bind(this));
        effects.windowClosed.connect(this.slotWindowClosed.bind(this));
        effects.windowDataChanged.connect(this.slotWindowDataChanged.bind(this));

        this.loadConfig();
    }

    loadConfig() {
        // animationTime() follows the system animation speed, like the rest of the rice's motion
        this.inDuration = animationTime(effect.readConfig("InDuration", 200) || 200);
        this.outDuration = animationTime(effect.readConfig("OutDuration", 160) || 160);
        this.inScale = effect.readConfig("InScale", 0.96);
        this.outScale = effect.readConfig("OutScale", 0.98);
    }

    static isAnimatedWindow(window) {
        // Plasmashell's own surfaces (panels, Glimpse, desktop) share one window class and animate
        // themselves; only its decorated windows (settings dialogs) are normal windows.
        if (window.windowClass == "plasmashell plasmashell"
                || window.windowClass == "plasmashell org.kde.plasmashell") {
            return window.hasDecoration;
        }

        const blacklistedTags = blacklist[window.windowClass];
        if (blacklistedTags && (blacklistedTags.length === 0 || blacklistedTags.includes(window.tag))) {
            return false;
        }

        if (window.hasDecoration) {
            return true;
        }

        // Menus, tooltips and dropdowns belong to rice_popups.
        if (window.popupWindow) {
            return false;
        }

        // Don't animate the outline and the screenlocker as it looks bad.
        if (window.lockScreen || window.outline) {
            return false;
        }

        // Override-redirect windows are usually UI bits that animate on their own terms.
        if (!window.managed) {
            return false;
        }

        return window.normalWindow || window.dialog;
    }

    setupForcedRoles(window) {
        // keep translucent windows blurred while they're being scaled
        window.setData(Effect.WindowForceBackgroundContrastRole, true);
        window.setData(Effect.WindowForceBlurRole, true);
    }

    cleanupForcedRoles(window) {
        window.setData(Effect.WindowForceBackgroundContrastRole, null);
        window.setData(Effect.WindowForceBlurRole, null);
    }

    slotWindowAdded(window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (!RiceWindowEffect.isAnimatedWindow(window)) {
            return;
        }
        if (!window.visible) {
            return;
        }
        if (effect.isGrabbed(window, Effect.WindowAddedGrabRole)) {
            return;
        }
        this.setupForcedRoles(window);
        window.riceInAnimation = animate({
            window: window,
            curve: QEasingCurve.OutCubic,
            duration: this.inDuration,
            animations: [
                {
                    type: Effect.Scale,
                    from: this.inScale
                },
                {
                    type: Effect.Opacity,
                    from: 0
                }
            ]
        });
    }

    slotWindowClosed(window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (!RiceWindowEffect.isAnimatedWindow(window)) {
            return;
        }
        if (!window.visible || window.skipsCloseAnimation) {
            return;
        }
        if (effect.isGrabbed(window, Effect.WindowClosedGrabRole)) {
            return;
        }
        if (window.riceInAnimation) {
            cancel(window.riceInAnimation);
            delete window.riceInAnimation;
        }
        this.setupForcedRoles(window);
        window.riceOutAnimation = animate({
            window: window,
            curve: QEasingCurve.InCubic,
            duration: this.outDuration,
            animations: [
                {
                    type: Effect.Scale,
                    to: this.outScale
                },
                {
                    type: Effect.Opacity,
                    to: 0
                }
            ]
        });
    }

    slotWindowDataChanged(window, role) {
        // another effect (e.g. magic lamp, a dialog parent) took the window over: let go
        if (role == Effect.WindowAddedGrabRole) {
            if (window.riceInAnimation && effect.isGrabbed(window, role)) {
                cancel(window.riceInAnimation);
                delete window.riceInAnimation;
                this.cleanupForcedRoles(window);
            }
        } else if (role == Effect.WindowClosedGrabRole) {
            if (window.riceOutAnimation && effect.isGrabbed(window, role)) {
                cancel(window.riceOutAnimation);
                delete window.riceOutAnimation;
                this.cleanupForcedRoles(window);
            }
        }
    }
}

new RiceWindowEffect();
