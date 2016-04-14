require 'digest/md5'
require 'securerandom'

module Embulk
  module Output
    class Bigquery < OutputPlugin
      class Helper
        def self.bq_type_from_embulk_type(embulk_type)
          case embulk_type
          when :boolean then 'BOOLEAN'
          when :long then 'INTEGER'
          when :double then 'FLOAT'
          when :string then 'STRING'
          when :timestamp then 'TIMESTAMP'
          when :json then 'STRING' # NOTE: Default is not RECORD since it requires `fields`
          else raise ArgumentError, "embulk type #{embulk_type} is not supported"
          end
        end

        # @return [Hash] name => column_option.
        # ToDo: recursively map fields?
        def self.column_options_map(column_options)
          (column_options || {}).map do |column_option|
            [column_option['name'], column_option]
          end.to_h
        end

        def self.fields_from_embulk_schema(task, schema)
          column_options_map = self.column_options_map(task['column_options'])
          schema.map do |column|
            column_name   = column[:name]
            embulk_type   = column[:type]
            column_option = column_options_map[column_name] || {}
            {}.tap do |field|
              field[:name]   = column_name
              field[:type]   = (column_option['type'] || bq_type_from_embulk_type(embulk_type)).upcase
              field[:mode]   = column_option['mode'] if column_option['mode']
              field[:fields] = deep_symbolize_keys(column_option['fields']) if column_option['fields']
            end
          end
        end

        def self.deep_symbolize_keys(obj)
          if obj.is_a?(Hash)
            obj.inject({}) do |options, (key, value)|
              options[(key.to_sym rescue key) || key] = deep_symbolize_keys(value)
              options
            end
          elsif obj.is_a?(Array)
            obj.map {|value| deep_symbolize_keys(value) }
          else
            obj
          end
        end

        def self.create_load_job_id(task, path, table, fields)
          elements = [
            path,
            Digest::MD5.file(path).hexdigest,
            task['dataset'],
            table,
            fields,
            task['source_format'],
            task['max_bad_records'],
            task['field_delimiter'],
            task['encoding'],
            task['ignore_unknown_values'],
            task['allow_quoted_newlines'],
          ]

          str = elements.map(&:to_s).join('')
          md5 = Digest::MD5.hexdigest(str)
          job_id = "embulk_load_job_#{md5}"
          Embulk.logger.debug { "embulk-output-bigquery: create_load_job_id(#{path}, #{table}) #=> #{job_id}" }
          job_id
        end

        def self.create_copy_job_id
          job_id = "embulk_copy_job_#{SecureRandom.uuid}"
          Embulk.logger.debug { "embulk-output-bigquery: create_copy_job_id #=> #{job_id}" }
          job_id
        end
      end
    end
  end
end
