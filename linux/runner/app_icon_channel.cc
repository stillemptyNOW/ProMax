#include "app_icon_channel.h"

#include <gdk-pixbuf/gdk-pixbuf.h>

#include <cstring>

static constexpr char kChannelName[] = "io.github.stillemptynow.promax/app_icon";

static FlMethodChannel* app_icon_channel = nullptr;

static GdkPixbuf* decode_icon(FlValue* image, GError** error) {
  g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new();
  const gboolean written = gdk_pixbuf_loader_write(
      loader, fl_value_get_uint8_list(image), fl_value_get_length(image), error);
  const gboolean closed = gdk_pixbuf_loader_close(loader, written ? error : nullptr);
  if (!written || !closed) {
    return nullptr;
  }
  GdkPixbuf* pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
  return pixbuf == nullptr ? nullptr : GDK_PIXBUF(g_object_ref(pixbuf));
}

static FlMethodResponse* set_app_icon(GtkWindow* window, FlValue* args) {
  FlValue* image = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                       ? fl_value_lookup_string(args, "image")
                       : nullptr;
  if (image == nullptr || fl_value_get_type(image) == FL_VALUE_TYPE_NULL) {
    gtk_window_set_icon(window, nullptr);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  if (fl_value_get_type(image) != FL_VALUE_TYPE_UINT8_LIST) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "INVALID_ICON", "The icon image must be PNG bytes", nullptr));
  }
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) pixbuf = decode_icon(image, &error);
  if (pixbuf == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "APPLY_FAILED",
        error != nullptr ? error->message : "The icon image could not be decoded",
        nullptr));
  }
  gtk_window_set_icon(window, pixbuf);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "setAppIcon") == 0) {
    response = set_app_icon(window, fl_method_call_get_args(method_call));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to answer an app icon call: %s", error->message);
  }
}

void app_icon_channel_register(FlPluginRegistry* registry, GtkWindow* window) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AppIconChannel");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_clear_object(&app_icon_channel);
  app_icon_channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      app_icon_channel, method_call_cb, g_object_ref(window), g_object_unref);
}
