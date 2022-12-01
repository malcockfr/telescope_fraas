# Telescope_fraas

Simple Telescope extension to view FRaaS projects

## Install

### Lunarvim

Add the extensions top your list of plugins:
```
lvim.plugins = {
  ...
  { "malcockfr/telescope_fraas",
    requires = { "tyru/open-browser.vim" },
  }
} 
```
Then run `:PackerSync` to install it.

## Setup

Tell Telescope to load the extension
```
lvim.builtin.telescope.on_config_done = function(telescope)
  ...
  telescope.load_extension "fraas"
end
```
In your Telescope sertup function (create on if needed) add the following,
I've shown the default value here but feel free to change it, it needs the two %s
placeholders which are the `project_name`:
```
lvim.builtin.telescope.extensions.fraas = {
  fraas = {
    terminal_cmd = "gnome-terminal --tab --title %s -- /usr/local/bin/forge shell %s"
  },
}
```

## Using it :)

To view builds for your current Git branch simply run
```
:Telescope fraas projects
```

The default action (enter) will open the build in the Codefresh UI.


## TODO
* Fix timeout issue with the gcloud projects list command
* Add more actions to open in GCP console
