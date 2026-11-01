#ifndef FLUTTER_APP_ICON_CHANNEL_H_
#define FLUTTER_APP_ICON_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

void app_icon_channel_register(FlPluginRegistry* registry, GtkWindow* window);

#endif  // FLUTTER_APP_ICON_CHANNEL_H_
