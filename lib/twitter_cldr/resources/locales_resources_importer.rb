# encoding: UTF-8

# Copyright 2012 Twitter, Inc
# http://www.apache.org/licenses/LICENSE-2.0

require 'fileutils'
require 'cldr/export'

require 'twitter_cldr/resources/download'

module TwitterCldr
  module Resources

    class LocalesResourcesImporter

      # NOTE: units.yml was NOT updated to cldr 24 (too many significant changes) - add back in when appropriate.
      #       Meanwhile, use ruby-cldr v0.0.2 and CLDR 22.1 to update units.yml files.
      LOCALE_COMPONENTS = %w[calendars languages numbers plurals lists layout currencies territories rbnf]  # units
      SHARED_COMPONENTS = %w[currency_digits_and_rounding rbnf_root numbering_systems segments_root territories_containment]

      # Arguments:
      #
      #   input_path  - path to a directory containing CLDR data
      #   output_path - output directory for imported YAML files
      #
      def initialize(input_path, output_path)
        @input_path  = input_path
        @output_path = output_path
      end

      def import
        prepare_ruby_cldr
        import_components
      end

      private

      def prepare_ruby_cldr
        TwitterCldr::Resources.download_cldr_if_necessary(@input_path)
        Cldr::Export::Data.dir = File.join(@input_path, 'common')
      end

      # Copies zh plurals to zh-Hant (they can share, but locale code needs to be different).
      #
      def copy_zh_hant_plurals
        File.open(File.join(@output_path, 'locales', 'zh-Hant', 'plurals.yml'), 'w:utf-8') do |output|
          data = YAML.load(File.read(File.join(@output_path, 'locales', 'zh', 'plurals.yml')))
          output.write(YAML.dump(:'zh-Hant' => data[:zh].gsub(":'zh'", ":'zh-Hant'")))
        end
      end

      def move_segments_root_file
        file_path = File.join(@output_path, 'shared', 'segments_root.yml')

        if File.file?(file_path)
          FileUtils.move(file_path, File.join(@output_path, 'shared', 'segments', 'segments_root.yml'))
        end
      end

      def import_components
        export_args = {
          :locales => TwitterCldr.supported_locales,
          :components => LOCALE_COMPONENTS,
          :target => File.join(@output_path, 'locales'),
          :merge => true  # fill in the gaps, eg fill in sub-locales like en_GB with en
        }

        Cldr::Export.export(export_args) do |component, locale, path|
          add_buddhist_calendar(component, locale, path)
          process_plurals(component, locale, path)
          downcase_territory_codes(component, locale, path)
          deep_symbolize(component, locale, path)
        end

        export_args = {
          :components => SHARED_COMPONENTS,
          :target => File.join(@output_path, 'shared'),
          :merge => true
        }

        Cldr::Export.export(export_args) do |component, locale, path|
          deep_symbolize(component, locale, path)
        end

        move_segments_root_file
        copy_zh_hant_plurals
      end

      def deep_symbolize(component, locale, path)
        return unless File.extname(path) == '.yml'
        data = YAML.load(File.read(path))

        File.open(path, 'w:utf-8') do |output|
          output.write(
            # Quote all strings for compat with 1.8. This is important because
            # RBNF syntax includes characters that are significant in the Yaml
            # syntax, like >, <, etc. Psych doesn't have problems parsing them,
            # but Syck does (ruby 1.8).
            TwitterCldr::Utils::YAML.dump(TwitterCldr::Utils.deep_symbolize_keys(data), {
              :quote_all_strings => true,
              :use_natural_symbols => true
            })
          )
        end
      end

      # CLDR stores territory codes uppercase. For consistency with how we
      # handle territory codes in methods relating to phone and postal codes,
      # we downcase them here.
      #
      # (There is also some trickery relating to three-digit UN "area codes"
      # used by CLDR; see comment of Utils::Territories::deep_normalize_territory_code_keys.)
      def downcase_territory_codes(component, locale, path)
        return unless component == 'Territories'

        data = YAML.load(File.read(path))
        data.keys.each do |l|
          data[l] = TwitterCldr::Shared::Territories.deep_normalize_territory_code_keys(data[l])
        end

        File.open(path, 'w:utf-8') do |output|
          output.write(YAML.dump(data))
        end
      end

      def process_plurals(component, locale, path)
        return unless component == 'Plurals'

        plural_rules = File.read(path)

        File.open(path.gsub(/rb$/, 'yml'), 'w:utf-8') do |output|
          output.write(YAML.dump({ locale => plural_rules }))
        end

        FileUtils.rm(path)
      end

      # TODO: export buddhist calendar from CLDR data instead of using BUDDHIST_CALENDAR constant.
      #
      def add_buddhist_calendar(component, locale, path)
        return unless component == 'Calendars' && locale == :th

        data = YAML.load(File.read(path))
        data['th']['calendars']['buddhist'] = BUDDHIST_CALENDAR

        File.open(path, 'w:utf-8') { |output| output.write(YAML.dump(data))}
      end

      BUDDHIST_CALENDAR = {
        'formats' => {
          'date' => {
            'default' => :'calendars.buddhist.formats.date.medium',
            'full'    => { 'pattern' => 'EEEEที่ d MMMM G y' },
            'long'    => { 'pattern' => 'd MMMM พ.ศ. #{y + 543}' },
            'medium'  => { 'pattern' => 'd MMM #{y + 543}' },
            'short'   => { 'pattern' => 'd/M/#{y + 543}' }
          }
        }
      }

    end

  end
end
