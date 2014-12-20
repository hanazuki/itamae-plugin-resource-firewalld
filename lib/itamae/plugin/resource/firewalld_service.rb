require 'itamae/resource/base'
require 'rexml/document'

module Itamae
  module Plugin
    module Resource
      class FirewalldService < ::Itamae::Resource::Base

        define_attribute :action, default: :create
        define_attribute :name, type: String, default_name: true

        define_attribute :short,       type: String, default: ''
        define_attribute :description, type: String, default: ''
        define_attribute :protocol,    type: String, default: ''
        define_attribute :port,        type: String, default: ''
        define_attribute :module_name, type: String, default: ''
        define_attribute :to_ipv4,     type: String, default: ''
        define_attribute :to_ipv6,     type: String, default: ''

        def pre_action
          current.status = current_status

          return if (@current_action != :create) || (current.status == :undefined)

          xml = run_specinfra(:get_file_content, service_xmlfile_path).stdout
          return if xml.empty?

          service = REXML::Document.new(xml).elements['/service'].elements

          if service['short']
            current.short = service['short'].text
          end

          if service['description']
            current.description = service['description'].text
          end

          if service['port']
            current.protocol = service['port'].attributes['protocol']
            current.port = service['port'].attributes['port']
          end

          if service['module']
            current.module_name = service['module'].attributes['name']
          end

          if service['destination']
            current.to_ipv4 = service['destination'].attributes['ipv4']
            current.to_ipv6 = service['destination'].attributes['ipv6']
          end
        end

        def action_create(options)
          run_specinfra(:move_file, build_xmlfile_on_remote, service_xmlfile_path)
          attributes.status = :defined
        end

        def action_delete(options)
          return if current.status == :undefined

          run_command(['firewall-cmd', '--permanent', '--delete-service', attributes.name])
          attributes.status = :undefined
        end

        private

        def build_xmlfile_on_remote
          local_path  = build_xmlfile_on_local
          remote_path = ::File.join(runner.tmpdir, Time.now.to_f.to_s)

          send_file(local_path, remote_path)
          remote_path
        end

        def build_xmlfile_on_local
          root_document  = ::REXML::Document.new
          root_document << ::REXML::XMLDecl.new('1.0', 'utf-8')
          @service_document = root_document.add_element('service')

          add_short_tag
          add_description_tag
          add_port_tag
          add_module_tag
          add_destination_tag

          f = Tempfile.open('itamae_firewalld_service')
          root_document.write(f)
          f.close
          f.path
        end

        def add_short_tag
          return if attributes.short.empty?

          short = @service_document.add_element('short')
          short.text = attributes.short unless attributes.short.empty?
        end

        def add_description_tag
          return if attributes.description.empty?

          description = @service_document.add_element('description')
          description.text = attributes.description unless attributes.description.empty?
        end

        def add_port_tag
          return if (attributes.protocol.empty? && attributes.port.empty?)

          node = @service_document.add_element('port')
          node.add_attribute('protocol', attributes.protocol) unless attributes.protocol.empty?
          node.add_attribute('port', attributes.port) unless attributes.port.empty?
        end

        def add_module_tag
          return if attributes.module_name.empty?

          node = @service_document.add_element('module')
          node.add_attribute('name', attributes.module_name) unless attributes.module_name.empty?
        end

        def add_destination_tag
          return if (attributes.to_ipv4.empty? && attributes.to_ipv6.empty?)

          node = @service_document.add_element('destination')
          node.add_attribute('ipv4', attributes.to_ipv4) unless attributes.to_ipv4.empty?
          node.add_attribute('ipv6', attributes.to_ipv6) unless attributes.to_ipv6.empty?
        end

        def service_xmlfile_path
          "/etc/firewalld/services/#{attributes.name}.xml"
        end

        def current_status
          command  = ['firewall-cmd', '--permanent', '--list-services']
          services = run_command(command).stdout.strip.split
          services.include?(attributes.name) ? :defined : :undefined
        end
      end
    end
  end
end
