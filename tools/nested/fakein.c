// Pointer and keys for the NESTED KWin of tools/nested/run.sh only (refuses any other compositor:
// WAYLAND_DISPLAY must be atom-spike). Uses KWin's fake-input protocol, allowed there by
// KWIN_WAYLAND_NO_PERMISSION_CHECKS.
// usage: fakein move X Y | click [left|right] | key CODE | type TEXT | wait MS | wheel N ...
#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <linux/input-event-codes.h>
#include "fake-input.h"
static struct org_kde_kwin_fake_input *fi;
static void reg(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t v) {
    if (!strcmp(iface, "org_kde_kwin_fake_input")) fi = wl_registry_bind(r, name, &org_kde_kwin_fake_input_interface, v < 4 ? v : 4);
}
static void unreg(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener rl = { reg, unreg };
static int keycode(char c, int *shift) {
    static const char *row = "abcdefghijklmnopqrstuvwxyz";
    static const int codes[] = {KEY_A,KEY_B,KEY_C,KEY_D,KEY_E,KEY_F,KEY_G,KEY_H,KEY_I,KEY_J,KEY_K,KEY_L,KEY_M,KEY_N,KEY_O,KEY_P,KEY_Q,KEY_R,KEY_S,KEY_T,KEY_U,KEY_V,KEY_W,KEY_X,KEY_Y,KEY_Z};
    *shift = 0;
    if (c >= 'A' && c <= 'Z') { *shift = 1; c = c - 'A' + 'a'; }
    const char *p = strchr(row, c); if (p && c) return codes[p - row];
    if (c == ' ') return KEY_SPACE; if (c >= '1' && c <= '9') return KEY_1 + (c - '1'); if (c == '0') return KEY_0;
    return 0;
}
static void key(struct wl_display *dpy, int code, int down) { org_kde_kwin_fake_input_keyboard_key(fi, code, down); wl_display_roundtrip(dpy); usleep(15000); }
int main(int argc, char **argv) {
    const char *w = getenv("WAYLAND_DISPLAY");
    if (!w || strcmp(w, "atom-spike")) { fprintf(stderr, "fakein: only for the nested atom-spike compositor\n"); return 2; }
    struct wl_display *dpy = wl_display_connect(NULL); if (!dpy) return 1;
    struct wl_registry *r = wl_display_get_registry(dpy); wl_registry_add_listener(r, &rl, NULL); wl_display_roundtrip(dpy);
    if (!fi) { fprintf(stderr, "no fake input\n"); return 1; }
    org_kde_kwin_fake_input_authenticate(fi, "fakein", "nested test"); wl_display_roundtrip(dpy);
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "move") && i + 2 < argc) {
            // a 1 px detour first: KWin drops a move to where the pointer already is, and only re-picks the
            // surface under the pointer on motion, so a click right after could go to a stale surface
            double x = atof(argv[i+1]), y = atof(argv[i+2]);
            org_kde_kwin_fake_input_pointer_motion_absolute(fi, wl_fixed_from_double(x + 1), wl_fixed_from_double(y));
            wl_display_roundtrip(dpy); usleep(16000);
            org_kde_kwin_fake_input_pointer_motion_absolute(fi, wl_fixed_from_double(x), wl_fixed_from_double(y));
            wl_display_roundtrip(dpy); usleep(16000);
            i += 2;
        }
        else if (!strcmp(argv[i], "click")) { int b = BTN_LEFT; if (i + 1 < argc && !strcmp(argv[i+1], "right")) { b = BTN_RIGHT; i++; } else if (i + 1 < argc && !strcmp(argv[i+1], "left")) i++;
            org_kde_kwin_fake_input_button(fi, b, 1); wl_display_roundtrip(dpy); usleep(30000); org_kde_kwin_fake_input_button(fi, b, 0); }
        else if (!strcmp(argv[i], "key") && i + 1 < argc) { int c = atoi(argv[++i]); key(dpy, c, 1); key(dpy, c, 0); }
        else if (!strcmp(argv[i], "type") && i + 1 < argc) { for (const char *s = argv[++i]; *s; s++) { int sh, c = keycode(*s, &sh); if (!c) continue; if (sh) key(dpy, KEY_LEFTSHIFT, 1); key(dpy, c, 1); key(dpy, c, 0); if (sh) key(dpy, KEY_LEFTSHIFT, 0); } }
        else if (!strcmp(argv[i], "wheel") && i + 1 < argc) { org_kde_kwin_fake_input_axis(fi, 0, wl_fixed_from_double(atof(argv[++i]))); }
        else if (!strcmp(argv[i], "wait") && i + 1 < argc) { wl_display_roundtrip(dpy); usleep(atoi(argv[++i]) * 1000); }
        wl_display_roundtrip(dpy);
    }
    wl_display_disconnect(dpy); return 0;
}
