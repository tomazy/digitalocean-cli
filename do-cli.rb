require 'rubygems'
require 'bundler/setup'

require 'digitalocean'
require 'dotenv'
require 'readline'
require 'terminal-table'

Dotenv.load

Digitalocean.client_id = ENV['DIGITALOCEAN_CLIENT_ID']
Digitalocean.api_key   = ENV['DIGITALOCEAN_API_KEY']

Thread.abort_on_exception = true

module DO
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

    def droplet(droplet_id=nil)
      print_item get_droplet(droplet_id), 'droplet'
    end

    def droplet_new
      watch_event(
        validate_response(
          Digitalocean::Droplet.create(
            name:               read_value('Droplet name', 'work'),
            size_id:            select(:sizes),
            image_id:           select(:snapshots),
            region_id:          select(:regions),
            ssh_key_ids:        load_all_ssh_key_ids,
            private_networking: false,
            backup_enabled:     false,
          ),
          :droplet
        ).event_id
      )
    end

    def droplet_destroy(droplet_id=nil)
      watch_event(
        validate_response(
          Digitalocean::Droplet.destroy(
            droplet_id || select(:droplets)
          ),
          :event_id
        )
      )
    end

    def droplet_snapshot(droplet_id=nil, name=nil)
      droplet_id ||= select(:droplets)
      watch_event(
        validate_response(
          Digitalocean::Droplet.snapshot(
            droplet_id,
            name: name || read_value('Name', default_snapshot_name(droplet_id))
          ),
          :event_id
        )
      )
    end

    def droplet_reboot(droplet_id=nil)
      watch_event(validate_response(Digitalocean::Droplet.reboot(droplet_id || select(:droplets)), :event_id))
    end

    def droplet_power_off(droplet_id=nil)
      watch_event(validate_response(Digitalocean::Droplet.power_off(droplet_id || select(:droplets)), :event_id))
    end

    def droplet_shutdown(droplet_id=nil)
      watch_event(validate_response(Digitalocean::Droplet.shutdown(droplet_id || select(:droplets)), :event_id))
    end

    def droplet_snapshot_and_destroy
      droplet_id = select(:droplets)

      puts "----- power off"
      droplet_power_off(droplet_id).join

      puts "----- taking snapshot"
      droplet_snapshot(droplet_id, default_snapshot_name(droplet_id)).join

      puts "----- waiting for droplet to become unlocked"
      wait_until_droplet_unlocked(droplet_id).join

      puts "----- power off"
      droplet_power_off(droplet_id).join

      puts "----- waiting for droplet to become unlocked"
      wait_until_droplet_unlocked(droplet_id).join

      puts "----- destroy"
      droplet_destroy(droplet_id).join

      puts "----- DONE!!!"
    end

    def snapshot(snapshot_id=nil)
      print_item get_snapshot(snapshot_id), 'Snapshot'
    end

    def snapshot_destroy
      puts validate_response(Digitalocean::Image.destroy(select(:snapshots)), :status)
    end

    def event(id)
      print_item get_event(id), 'Event'
    end

    def wait_until_droplet_unlocked(droplet_id)
      Thread.new do
        loop do
          droplet = get_droplet(droplet_id)
          break unless droplet.locked
          sleep 1
        end
      end
    end

    def store_ip_in_dot_file(droplet_id=nil)
      droplet = get_droplet(droplet_id || select(:droplets))

      name = droplet['name'].downcase
      ip   = droplet['ip_address']

      file_name = File.expand_path "~/.#{name}-ip"

      File.open(file_name, "w") do |f|
        f.write "DO_SERVER=#{ip}\n"
      end
      file_name
    end

    def help
      puts """
        Commands:
          DO.help

          DO.droplet [ID]
          DO.droplet_new
          DO.droplet_destroy [ID]
          DO.droplet_snapshot [ID]
          DO.droplet_shutdown [ID]
          DO.droplet_power_off [ID]
          DO.droplet_snapshot_and_destroy

          DO.snapshot [ID]
          DO.snapshot_destroy [ID]

          DO.droplets(force=false)
          DO.regions(force=false)
          DO.sizes(force=false)
          DO.snapshots(force=false)

          DO.store_ip_in_dot_file

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

    def get_event(id)
      validate_response Digitalocean::Event.find(id), :event
    end

    def get_droplet(droplet_id=nil)
      validate_response(Digitalocean::Droplet.find(droplet_id || select(:droplets)), :droplet)
    end

    def get_snapshot(snapshot_id=nil)
      validate_response(Digitalocean::Image.find(snapshot_id || select(:snapshots)), :image)
    end

    def default_snapshot_name(droplet_id)
      name = get_droplet(droplet_id)['name']
      name + "-" + Time.now.strftime('%Y/%m/%d %H:%M')
    end

    def validate_response(resp, name)
      return resp.public_send(name) if resp.status == 'OK'
      raise resp.message
    end

    def watch_event(id)
      puts "Watching event ##{id}"
      Thread.new do
        loop do
          event = get_event(id)
          puts "       Event: ##{event.id}, #{event.percentage || 0}%"
          break if event.action_status == 'done'
          sleep 1
        end
      end
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

    def print_item(item, title=nil)
      headings = ['Key', 'Value']
      rows = item.to_h.to_a

      t = table headings: headings, rows: rows, title: title
      puts t
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
