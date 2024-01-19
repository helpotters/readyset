require 'colorize'
require 'erb'
require 'progressbar'

namespace :readyset do
  namespace :caches do
    desc 'Dumps the set of caches that currently exist on ReadySet to a file'
    task dump: :environment do
      Rails.application.eager_load!

      template = File.read(File.join(File.dirname(__FILE__), '../templates/caches.rb.tt'))

      queries = Readyset::Query::CachedQuery.all

      f = File.new(Readyset.configuration.migration_path, 'w')
      f.write(ERB.new(template, trim_mode: '-').result(binding))
      f.close
    end

    desc 'Synchronizes the caches on ReadySet such that the caches on ReadySet match those ' \
      'listed in db/readyset_caches.rb'
    task migrate: :environment do
      Rails.application.eager_load!

      file = Readyset.configuration.migration_path

      # We load the definition of the `Readyset::Caches` subclass in the context of a
      # container object so we can be sure that we are never re-opening a previously-defined
      # subclass of `Readyset::Caches`. When the container object is garbage collected, the
      # definition of the `Readyset::Caches` subclass is garbage collected too
      container = Object.new
      container.instance_eval(File.read(file))
      caches_in_migration_file = container.singleton_class::ReadysetCaches.caches.index_by(&:text)
      caches_on_readyset = Readyset::Query::CachedQuery.all.index_by(&:text)

      to_drop = caches_on_readyset.keys - caches_in_migration_file.keys
      to_create = caches_in_migration_file.keys - caches_on_readyset.keys

      if to_drop.size.positive? || to_create.size.positive?
        dropping = 'Dropping'.red
        creating = 'creating'.green
        print "#{dropping} #{to_drop.size} caches and #{creating} #{to_create.size} caches. " \
          'Continue? (y/n) '
        $stdout.flush
        y_or_n = STDIN.gets.strip

        if y_or_n == 'y'
          if to_drop.size.positive?
            bar = ProgressBar.create(title: 'Dropping caches', total: to_drop.size)

            to_drop.each do |text|
              bar.increment
              Readyset.drop_cache!(caches_on_readyset[text].name)
            end
          end

          if to_create.size.positive?
            bar = ProgressBar.create(title: 'Creating caches', total: to_create.size)

            to_create.each do |text|
              bar.increment
              cache = caches_in_migration_file[text]
              Readyset.create_cache!(sql: text, always: cache.always)
            end
          end
        end
      else
        puts 'Nothing to do'
      end
    end
  end
end
