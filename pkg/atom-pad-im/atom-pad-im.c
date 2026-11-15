// Atom Pad's input method: lets the game controller's on-screen keyboard type ANY character into the focused
// text field (accents on a US layout, symbols no key makes), the way an input method does, instead of
// through the clipboard.
//
// KWin starts it (kwinrc [Wayland] InputMethod = its .desktop file; build.sh sets that up) and gives it the
// privileged input-method protocol (zwp_input_method_v1). Whenever an app's text field takes the focus KWin
// hands it a context, and it can commit text into that field. It draws nothing and never grabs the keyboard:
// typing on a real keyboard goes on as before.
//
// D-Bus (session): org.zinoxx.AtomPadIM /IM, interface org.zinoxx.AtomPadIM
//   Commit(s text) -> b      put the text into the focused field (false: no text field has the focus)
//   Active() -> b            a text field has the focus
//   signal Field(b on, u hint, u purpose)    a text field took the focus / let go (hint: the content type,
//                            zwp_text_input_v1 values: password, numeric...)
// bin/pad.py (the controller daemon) calls Commit for characters its keyboard layout can't type.
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <systemd/sd-bus.h>
#include <time.h>
#include <wayland-client.h>

#include "input-method-unstable-v1-client-protocol.h"

static struct wl_display *display;
static struct zwp_input_method_v1 *im;
static struct zwp_input_method_context_v1 *ctx;     // the focused text field's context (NULL: none)
static uint32_t serial;                             // the latest commit_state: commits must carry it
static uint32_t hint, purpose;
static sd_bus *bus;
static volatile sig_atomic_t quit;

#define NAME "org.zinoxx.AtomPadIM"
#define PATH "/IM"

static void tell(int on)
{
    sd_bus_emit_signal(bus, PATH, NAME, "Field", "buu", on, hint, purpose);
    sd_bus_flush(bus);
}

// ---- the focused field's context
static void surrounding_text(void *d, struct zwp_input_method_context_v1 *c, const char *text, uint32_t cursor, uint32_t anchor) {}
static void reset(void *d, struct zwp_input_method_context_v1 *c) {}
static void content_type(void *d, struct zwp_input_method_context_v1 *c, uint32_t h, uint32_t p)
{
    if (c != ctx || (h == hint && p == purpose))
        return;
    hint = h;
    purpose = p;
    tell(1);
}
static void invoke_action(void *d, struct zwp_input_method_context_v1 *c, uint32_t button, uint32_t index) {}
static void commit_state(void *d, struct zwp_input_method_context_v1 *c, uint32_t s)
{
    if (c == ctx)
        serial = s;
}
static void preferred_language(void *d, struct zwp_input_method_context_v1 *c, const char *lang) {}

static const struct zwp_input_method_context_v1_listener context_listener = {
    surrounding_text, reset, content_type, invoke_action, commit_state, preferred_language,
};

// ---- KWin: a text field took the focus, or let it go
static void activate(void *d, struct zwp_input_method_v1 *m, struct zwp_input_method_context_v1 *c)
{
    if (ctx)
        zwp_input_method_context_v1_destroy(ctx);
    ctx = c;
    serial = 0;
    hint = purpose = 0;
    zwp_input_method_context_v1_add_listener(ctx, &context_listener, NULL);
    tell(1);
}
static void deactivate(void *d, struct zwp_input_method_v1 *m, struct zwp_input_method_context_v1 *c)
{
    if (c == ctx) {
        ctx = NULL;
        tell(0);
    }
    zwp_input_method_context_v1_destroy(c);
}
static const struct zwp_input_method_v1_listener im_listener = { activate, deactivate };

static void global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version)
{
    if (strcmp(iface, zwp_input_method_v1_interface.name) == 0) {
        im = wl_registry_bind(r, name, &zwp_input_method_v1_interface, 1);
        zwp_input_method_v1_add_listener(im, &im_listener, NULL);
    }
}
static void global_remove(void *d, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener registry_listener = { global, global_remove };

// ---- D-Bus
static int method_commit(sd_bus_message *m, void *u, sd_bus_error *e)
{
    const char *text = NULL;
    int r = sd_bus_message_read(m, "s", &text);
    if (r < 0)
        return r;
    if (!ctx || !text)
        return sd_bus_reply_method_return(m, "b", 0);
    zwp_input_method_context_v1_commit_string(ctx, serial, text);
    wl_display_flush(display);
    return sd_bus_reply_method_return(m, "b", 1);
}
static int method_active(sd_bus_message *m, void *u, sd_bus_error *e)
{
    return sd_bus_reply_method_return(m, "b", ctx != NULL);
}
static const sd_bus_vtable vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Commit", "s", "b", method_commit, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Active", "", "b", method_active, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_SIGNAL("Field", "buu", 0),
    SD_BUS_VTABLE_END,
};

static void stop(int s) { quit = 1; }

int main(void)
{
    signal(SIGTERM, stop);
    signal(SIGINT, stop);
    display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "atom-pad-im: no Wayland display (KWin starts this as its input method)\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!im) {
        fprintf(stderr, "atom-pad-im: KWin offers no input method protocol (it gives it only to the input method it started)\n");
        return 1;
    }
    int r = sd_bus_open_user(&bus);
    if (r >= 0)
        r = sd_bus_add_object_vtable(bus, NULL, PATH, NAME, vtable, NULL);
    if (r >= 0)     // (a new one takes over from an old one KWin hasn't reaped yet)
        r = sd_bus_request_name(bus, NAME, SD_BUS_NAME_REPLACE_EXISTING | SD_BUS_NAME_ALLOW_REPLACEMENT);
    if (r < 0) {
        fprintf(stderr, "atom-pad-im: D-Bus: %s\n", strerror(-r));
        return 1;
    }
    fprintf(stderr, "atom-pad-im: ready\n");

    struct pollfd fds[2] = { { .fd = wl_display_get_fd(display), .events = POLLIN }, { .fd = sd_bus_get_fd(bus) } };
    while (!quit) {
        while (wl_display_prepare_read(display) != 0)
            wl_display_dispatch_pending(display);
        wl_display_flush(display);
        fds[1].events = sd_bus_get_events(bus);
        uint64_t usec = UINT64_MAX;
        sd_bus_get_timeout(bus, &usec);
        int timeout = -1;
        if (usec != UINT64_MAX) {
            struct timespec ts;
            clock_gettime(CLOCK_MONOTONIC, &ts);
            uint64_t now = (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
            timeout = usec > now ? (int)((usec - now + 999) / 1000) : 0;
        }
        if (poll(fds, 2, timeout) < 0) {
            wl_display_cancel_read(display);
            if (errno == EINTR)
                continue;
            break;
        }
        if (fds[0].revents & POLLIN) {
            if (wl_display_read_events(display) < 0)
                break;
        } else {
            wl_display_cancel_read(display);
        }
        if (fds[0].revents & (POLLERR | POLLHUP))
            break;
        if (wl_display_dispatch_pending(display) < 0)
            break;
        while ((r = sd_bus_process(bus, NULL)) > 0)
            ;
        if (r < 0)
            break;
    }
    if (ctx)
        zwp_input_method_context_v1_destroy(ctx);
    sd_bus_flush_close_unref(bus);
    wl_display_disconnect(display);
    return 0;
}
