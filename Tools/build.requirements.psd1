@{
    PSDependOptions  = @{
        Target = "CurrentUser"
    }

    InvokeBuild      = "latest"
    BuildHelpers     = @{
        Parameters = @{
            AllowClobber = $true
        }
        Version    = "latest"
    }
    Pester           = @{
        Parameters = @{
            SkipPublisherCheck = $true
        }
        Version    = "4.3.1"
    }
}
