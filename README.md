# Dev Container Features

> This repo provides features for devcontainers to aid my daily development work. This repository follows the [dev container Feature distribution specification](https://containers.dev/implementors/features-distribution/).
>
> To provide feedback or report issues and ideas, please leave a comment in the discussions page of this repository.

## Features

Each sub-section below shows a sample `devcontainer.json` alongside example usage of the Feature. Every feature can have their own configuration options, so navigate to `src/the-feature/README.md` to discover more about every feature.

### `php-cli`

This feature will install PHP CLI inside the built container. Microsoft provides their own PHP feature, but I needed to be able to define what extensions to install.

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/harrysbaraini/devcontainers-features/php-cli": {
            "version": "8.2",
            "packages": "imagick,gd,sodium"
        }
    }
}
```

### `nginx-unit-php`

Tthis feature will install [Nginx Unit](https://unit.nginx.org/) inside the built container. **It requires a php-cli already installed in the container**. You can use my php-cli feature for that :P

Unit is a lightweight open-source server built by Nginx, with capabilities to deliver static media assets, an application server, and a reverse proxy. I really recommend you to try it.
If you work with PHP you know that the great Nginx needs php-fpm to deliver PHP applications - **that's not the case** with Unit - You just ditch fpm from your servers! Unfortunately Unit is not as known as it should be.
I'm not saying that you should just start using it on production: I'm not a server manager so I don't know how good it's compared to a fine-tuned setup with established servers. But for development environment I think
it really shines at how easy it's to configure. I didn't benchmark Unit against other web servers, but here are some links where you can find out about it:

- [Nginx Unit. Running NodeJs, Golang and Php on the one App Server](https://faun.pub/nginx-unit-running-nodejs-golang-and-php-on-the-one-app-server-a3ff349a61a3) - _Mikhail Panfilov_
- [Nginx Unit - A new way to run web applications](https://techblog.schwarz/posts/nginx-unit/#:~:text=Nginx%20Unit%20vs.&text=Unit%20is%20more%20robust%20under,the%20same%20instance%20remain%20untouched) - _Schwarz_
- [Comparing PHP-FPM, NGINX Unit, and Laravel Octane](https://habr.com/en/articles/646397/) - _HABR / @straykerwl_

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        // Other features...
        "ghcr.io/harrysbaraini/devcontainers-features/nginx-unit-php": {
            "app_root": "${containerWorkspaceFolder}/my-app/public"
        }
    }
}
```

## A Laravel Example

```jsonc
{
	"name": "My Laravel Application",
	"remoteUser": "vscode",
	"image": "mcr.microsoft.com/devcontainers/base:jammy",
	"workspaceFolder": "/workspace",
    "workspaceMount": "source=code,target=/workspace/my-project,type=volume",
	"features": {
		"./devcontainers-features/src/php-cli": {
            "version": "8.2",
            "packages": "imagick,gd"
        },
        "./devcontainers-features/src/nginx-unit-php": {
            // "app_root" could be omitted as this is the default app_root value.
            "app_root": "${containerWorkspaceFolder}/public",
            // A custom port...
            "port": "8080"
        }
	},
	"customizations": {
        "vscode": {
            "settings": {
                "terminal.integrated.defaultProfile.linux": "bash",
                "php.executablePath": "/usr/local/bin/php"
            },
            "extensions": [
                "DEVSENSE.composer-php-vscode",
                "DEVSENSE.phptools-vscode",
                "DEVSENSE.profiler-php-vscode",
                "mikestead.dotenv"
            ]
        }
    }
}
```
