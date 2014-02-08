Digital Ocean Client
====================

1. `bundle install`
1. create `./.env` file with Digital Ocean credentials
1. `irb -r ./do-cli.rb`

        Commands:
          DO.help

          DO.droplet_new
          DO.droplet_destroy
          DO.droplet_take_snapshot
          DO.droplet_power_off
          DO.snapshot_destroy

          DO.droplets
          DO.regions
          DO.sizes
          DO.snapshots
          DO.event ID

Most of the API responses are cached. To force hitting the server again call the listing methods with `true` param. E.g.

    DO.droplets true
