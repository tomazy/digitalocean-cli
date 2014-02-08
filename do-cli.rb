#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'

require 'digitalocean'
require 'dotenv'
require 'readline'
require 'terminal-table'

Dotenv.load

Digitalocean.client_id = ENV['DIGITALOCEAN_CLIENT_ID']
Digitalocean.api_key   = ENV['DIGITALOCEAN_API_KEY']

class DO
  COLUMNS_MAP = {
    snapshots: [:id, :name],
    sizes: [:id, :name],
    regions: [:id, :name],
    droplets:  [:id, :name, :ip_address, :status, :locked, :created_at, :size_id, :region_id]
  }

  class << self
    def sizes(force=false)
      print_collection :sizes, force
    end

    def regions(force=false)
      print_collection :regions, force
    end

    def droplets(force=false)
      print_collection :droplets, force
    end

    def snapshots(force=false)
      print_collection :snapshots, force
    end

    def droplet_new
      print_response Digitalocean::Droplet.create(
        name:               read_value('Droplet name', 'work'),
        size_id:            select(:sizes),
        image_id:           select(:snapshots),
        region_id:          select(:regions),
        ssh_key_ids:        load_all_ssh_key_ids,
        private_networking: false,
        backup_enabled:     false,
      )
    end

    def droplet_destroy
      print_response Digitalocean::Droplet.destroy select(:droplets)
    end

    def droplet_take_snapshot
      print_response Digitalocean::Droplet.snapshot select(:droplets), name: read_value('Name', Date.today.strftime('%d/%m'))
    end

    def droplet_power_off
      print_response Digitalocean::Droplet.power_off select(:droplets)
    end

    def snapshot_destroy
      print_response Digitalocean::Image.destroy select(:snapshots)
    end

    def event(id)
      puts Digitalocean::Event.find(id).inspect
    end

    def help
      puts """
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

      """
    end

    private

    def get_snapshots(force=false)
      cache(:snapshots, force) { Digitalocean::Image.all(filter: 'my_images').images }
    end

    def get_sizes(force=false)
      cache(:sizes, force) { Digitalocean::Size.all.sizes }
    end

    def get_droplets(force=false)
      cache(:droplets, force) { Digitalocean::Droplet.all.droplets }
    end

    def get_regions(force=false)
      cache(:regions, force) { Digitalocean::Region.all.regions }
    end

    def table(options)
      Terminal::Table.new options
    end

    def cache(id, force=false)
      @_cache ||= {}
      @_cache[id] = yield if @_cache[id].nil? || force
      @_cache[id]
    end

    def print_collection(collection, force=false)
      list = send "get_#{collection}", force
      print_table collection.upcase, list, *COLUMNS_MAP[collection]
      yield list if block_given?
    end

    def select(collection)
      print_collection collection do |list|
        raise 'List empty' if list.empty?
        select_from_list(list).id
      end
    end

    def table_header(name)
      name.to_s.split('_').map(&:capitalize).join(' ')
    end

    def print_table title, list, *cols
      headings = ['#'] + cols.map { |a| table_header a }
      rows = list.map.with_index do |el, idx|
        [idx + 1] + cols.map {|c| el.public_send c }
      end

      t = table headings: headings, rows: rows, title: title
      t.align_column 0, :right
      puts t
    end

    def select_from_list list
      nr = read_value 'Select from list', 1
      idx = nr.to_i - 1
      list[idx]
    end

    def print_response resp
      puts resp.inspect
    end

    def read_value(prompt, default = nil)
      val = Readline.readline("#{prompt} [#{default}]>", true).chomp
      val.empty? ? default : val
    end

    def load_all_ssh_key_ids
      Digitalocean::SshKey.all.ssh_keys.map(&:id).join(',')
    end
  end
end

DO.help
