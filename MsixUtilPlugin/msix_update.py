import sublime
import sublime_plugin


class UpdateCheckCommand(sublime_plugin.WindowCommand):
    def run(self):
        print("update_check command invoked")
        pass