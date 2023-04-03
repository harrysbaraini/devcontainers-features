
# Nginx Unit (nginx-unit-php)

Nginx Unit as an app server for your PHP application. SUPPORT FOR UBUNTU 22.04 for now.

## Example Usage

```json
"features": {
    "ghcr.io/harrysbaraini/devcontainers-features/nginx-unit-php:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| port | The port to run Unit | string | 80 |
| app_root | Root path of the site | string | /var/www/html/public |
| config_path | A custom JSON file to load as Unit configuration. It must be exist inside the container. If not provided, the auto-generated file will be used. | string | /nginx-unit/config.json |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/harrysbaraini/devcontainers-features/blob/main/src/nginx-unit-php/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
