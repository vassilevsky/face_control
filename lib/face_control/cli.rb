require 'logger'
require 'docopt'
require 'stash'

module FaceControl
  class CLI
    USAGE = File.read("#{File.dirname(__FILE__)}/../../USAGE")

    def run
      logger = Logger.new(STDOUT)
      project, repository, pull_request_id, ignored_severities = arguments
      pull_request = Stash::Config.new.server(logger).repository(project, repository).pull_request(pull_request_id)

      logger.info('Running checkers...')
      comments = check(pull_request, ignored_severities, logger)
      return if comments.empty?

      logger.info("#{comments.size} comments have been created. Posting only those for added lines...")
      add_comments(pull_request, comments)
    end

    def check(pull_request, ignored_severities, logger)
      unless ignored_severities.empty?
        logger.info("Skipping RuboCop offenses with severities: #{ignored_severities.join(', ')}.")
      end

      filenames = pull_request.filenames_with_added_lines

      checkers = [
        FaceControl::CheckerRunner.new(FaceControl::Checkers::RuboCop, filenames, ignored_severities: ignored_severities),
        FaceControl::CheckerRunner.new(FaceControl::Checkers::CoffeeLint, filenames),
        FaceControl::CheckerRunner.new(FaceControl::Checkers::Comments, filenames)
      ]

      checkers.map(&:comments).flatten
    end

    def add_comments(pull_request, comments)
      comments.each do |comment|
        pull_request.add_comment(comment.file, comment.line, comment.text)
      end
    end

    private

    def arguments
      args = Docopt.docopt(USAGE)

      project = args['<project>']
      repository = args['<repository>']
      pull_request_id = args['<pull_request_id>']

      ignored_severities = []
      if args['--skip-severity']
        ignored_severities = args['--skip-severity'].split(',')
      end

      [project, repository, pull_request_id, ignored_severities]
    rescue Docopt::Exit => e
      puts e.message
      exit(1)
    end
  end
end
