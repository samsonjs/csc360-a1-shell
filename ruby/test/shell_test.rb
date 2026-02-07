require "minitest/autorun"
require "etc"
require "open3"
require "timeout"
$LOAD_PATH.unshift(File.expand_path("..", __dir__))
require_relative "../shell/job_control"
require_relative "../shell/logger"

class ShellTest < Minitest::Test
  TRIVIAL_SHELL_SCRIPT = "#!/bin/sh\ntrue".freeze

  A1_PATH = ENV.fetch("A1_PATH", "./a1").freeze
  COMPAT_PROFILE = ENV["A1_TEST_PROFILE"] == "compat"

  def setup
    FileUtils.mkdir_p("test_bin")
  end

  def teardown
    FileUtils.rm_rf("test_bin")
  end

  def unique_shell_script(code)
    "#!/bin/sh\necho '#{code}'"
  end

  def requires_extended_shell!(feature)
    return unless COMPAT_PROFILE

    skip "requires extended shell feature: #{feature}"
  end

  def test_expands_environment_variables
    assert_equal Dir.home, `#{A1_PATH} -c 'echo $HOME'`.chomp
    assert_equal Dir.home, `#{A1_PATH} -c 'echo ${HOME}'`.chomp
    assert_equal "#{Dir.home} #{Dir.home}", `#{A1_PATH} -c 'echo ${HOME} ${HOME}'`.chomp
  end

  def test_fails_on_unknown_variables
    assert_equal false, system("#{A1_PATH} -c 'echo $DEFINITELY_DOES_NOT_EXIST' 2>/dev/null")
  end

  def test_expands_tilde
    assert_equal Dir.home, `#{A1_PATH} -c 'echo ~'`.chomp
  end

  def test_splits_words
    assert_equal "a b c", `#{A1_PATH} -c 'echo a b c'`.chomp
  end

  def test_respects_double_quotes
    assert_equal "a b", `#{A1_PATH} -c 'echo \"a b\"'`.chomp
  end

  def test_respects_escaped_double_quote_in_double_quotes
    assert_equal "a\"b", `#{A1_PATH} -c 'echo \"a\\\"b\"'`.chomp
  end

  def test_respects_single_quotes
    assert_equal "a b", `#{A1_PATH} -c \"echo 'a b'\"`.chomp
  end

  def test_respects_backslash_escaping
    assert_equal "a b", `#{A1_PATH} -c 'echo a\\ b'`.chomp
  end

  def test_expands_globs
    File.write("globtest_a.txt", TRIVIAL_SHELL_SCRIPT)
    File.write("globtest_b.txt", TRIVIAL_SHELL_SCRIPT)
    output = `#{A1_PATH} -c 'echo globtest_*.txt'`.chomp.split
    assert_equal ["globtest_a.txt", "globtest_b.txt"], output.sort
  ensure
    FileUtils.rm_f("globtest_a.txt")
    FileUtils.rm_f("globtest_b.txt")
  end

  def test_does_not_reglob_expanded_paths
    File.write("globspecial_a.txt", TRIVIAL_SHELL_SCRIPT)
    File.write("globspecial_[a].txt", TRIVIAL_SHELL_SCRIPT)
    output = `#{A1_PATH} -c 'echo globspecial_*.txt'`.chomp.split
    assert_equal ["globspecial_[a].txt", "globspecial_a.txt"], output.sort
  ensure
    FileUtils.rm_f("globspecial_a.txt")
    FileUtils.rm_f("globspecial_[a].txt")
  end

  def test_does_not_expand_escaped_dollar
    assert_equal "$HOME", `#{A1_PATH} -c 'echo \\$HOME'`.chomp
  end

  def test_expands_brace_expansion
    requires_extended_shell!("brace expansion")
    assert_equal "a b", `#{A1_PATH} -c 'echo {a,b}'`.chomp
  end

  def test_expands_command_substitution_backticks
    assert_equal "hi", %x(#{A1_PATH} -c 'echo `echo hi`').chomp
  end

  def test_expands_command_substitution_dollar_paren
    assert_equal "hi", `#{A1_PATH} -c 'echo $(echo hi)'`.chomp
  end

  def test_keeps_control_operators_inside_command_substitution
    requires_extended_shell!("nested command parsing in substitutions")
    semicolon_stdout, semicolon_stderr, semicolon_status = Open3.capture3(A1_PATH, "-c", "echo $(echo hi; echo bye)")
    assert semicolon_status.success?, semicolon_stderr
    assert_equal "hi bye\n", semicolon_stdout

    and_stdout, and_stderr, and_status = Open3.capture3(A1_PATH, "-c", "echo $(echo hi && echo bye)")
    assert and_status.success?, and_stderr
    assert_equal "hi bye\n", and_stdout
  end

  def test_expands_command_substitution_with_escaped_quote
    requires_extended_shell!("escaped quote handling in substitutions")
    assert_equal "a\"b", `#{A1_PATH} -c 'echo $(printf \"%s\" \"a\\\"b\")'`.chomp
  end

  def test_expands_arithmetic
    assert_equal "3", `#{A1_PATH} -c 'echo $((1 + 2))'`.chomp
  end

  def test_expands_arithmetic_with_variables
    requires_extended_shell!("arithmetic variable lookup")
    assert_equal "3", `A1_NUM=2 #{A1_PATH} -c 'echo $((A1_NUM + 1))'`.chomp
  end

  def test_expands_tilde_user
    user = Etc.getlogin
    skip "no login user" unless user
    assert_equal Dir.home(user), `#{A1_PATH} -c 'echo ~#{user}'`.chomp
  end

  def test_expands_parameter_default_value
    requires_extended_shell!("${var:-fallback}")
    assert_equal "fallback", `#{A1_PATH} -c 'echo ${A1_UNSET_VAR:-fallback}'`.chomp
  end

  def test_expands_parameter_default_value_with_variable_reference
    requires_extended_shell!("${var:-$OTHER}")
    assert_equal Dir.home, `#{A1_PATH} -c 'echo ${A1_UNSET_VAR:-$HOME}'`.chomp
  end

  def test_expands_parameter_default_value_with_command_substitution
    requires_extended_shell!("${var:-$(...)}")
    assert_equal "hi", `#{A1_PATH} -c 'echo ${A1_UNSET_VAR:-$(echo hi)}'`.chomp
  end

  def test_expands_glob_from_parameter_default_value
    requires_extended_shell!("glob expansion from parameter defaults")
    File.write("default_glob_a.txt", TRIVIAL_SHELL_SCRIPT)
    File.write("default_glob_b.txt", TRIVIAL_SHELL_SCRIPT)
    output = `#{A1_PATH} -c 'printf "%s\n" ${A1_UNSET_GLOB_VAR:-default_glob_*.txt}'`.lines.map(&:chomp).sort
    assert_equal ["default_glob_a.txt", "default_glob_b.txt"], output
  ensure
    FileUtils.rm_f("default_glob_a.txt")
    FileUtils.rm_f("default_glob_b.txt")
  end

  def test_reports_command_substitution_failure_with_status
    requires_extended_shell!("command substitution error propagation")
    _stdout, stderr, status = Open3.capture3(A1_PATH, "-c", "echo $(exit 7)")
    refute status.success?
    assert_match(/command substitution failed/, stderr)
    assert_match(/exit 7/, stderr)
    refute_match(/No such file or directory/, stderr)
  end

  def test_expands_nested_defaults_with_substitution_and_arithmetic
    requires_extended_shell!("nested defaults and arithmetic")
    command = 'echo ${A1_OUTER_UNSET:-${A1_MIDDLE_UNSET:-${A1_INNER_UNSET:-$(printf "%s" "calc_$((2+3))")}}}'
    assert_equal "calc_5", `#{A1_PATH} -c '#{command}'`.chomp
  end

  def test_matches_sh_backslash_parity_before_dollar_and_backticks
    [1, 2, 3, 4].each do |count|
      command = "printf \"%s\\n\" #{"\\" * count}$HOME"
      shell_stdout, _shell_stderr, shell_status = Open3.capture3(A1_PATH, "-c", command)
      sh_stdout, _sh_stderr, sh_status = Open3.capture3("/bin/sh", "-c", command)

      assert_equal sh_status.success?, shell_status.success?, "status mismatch for #{command.inspect}"
      assert_equal sh_stdout, shell_stdout, "stdout mismatch for #{command.inspect}"
    end

    [1, 2, 3, 4].each do |count|
      command = "printf \"%s\\n\" #{"\\" * count}`echo hi`"
      shell_stdout, _shell_stderr, shell_status = Open3.capture3(A1_PATH, "-c", command)
      sh_stdout, _sh_stderr, sh_status = Open3.capture3("/bin/sh", "-c", command)

      assert_equal sh_status.success?, shell_status.success?, "status mismatch for #{command.inspect}"
      assert_equal sh_stdout, shell_stdout, "stdout mismatch for #{command.inspect}"
    end
  end

  def test_does_not_expand_escaped_command_substitution_dollar_paren_in_double_quotes
    assert_equal "$(echo hi)", `#{A1_PATH} -c 'echo "\\$(echo hi)"'`.chomp
  end

  def test_does_not_expand_escaped_command_substitution_backticks_in_double_quotes
    assert_equal "`echo hi`", %x(#{A1_PATH} -c 'echo "\\`echo hi\\`"').chomp
  end

  def test_combines_expansions_in_defaults_and_subcommands
    requires_extended_shell!("composed substitutions and defaults")
    File.write("combo_a.txt", TRIVIAL_SHELL_SCRIPT)
    File.write("combo_b.txt", TRIVIAL_SHELL_SCRIPT)

    command = [
      "printf \"<%s>\\n\"",
      "${A1_UNSET_COMPLEX_TEST_VAR:-$(printf \"%s\" \"default_$((1+2))\")}",
      "$(printf \"%s\" \"combo_*.txt\")",
      "\"$(printf \"%s\" \"quoted value\")\"",
      "{left,right}",
      "~"
    ].join(" ")
    output = `#{A1_PATH} -c '#{command}'`.lines.map(&:chomp)

    assert_equal "<default_3>", output[0]
    assert_equal ["<combo_a.txt>", "<combo_b.txt>"], output[1, 2].sort
    assert_equal "<quoted value>", output[3]
    assert_equal "<left>", output[4]
    assert_equal "<right>", output[5]
    assert_equal "<#{Dir.home}>", output[6]
    assert_equal 7, output.length
  ensure
    FileUtils.rm_f("combo_a.txt")
    FileUtils.rm_f("combo_b.txt")
  end

  def test_reports_parse_errors_without_ruby_backtrace
    _stdout, stderr, status = Open3.capture3(A1_PATH, "-c", "echo \"unterminated")
    refute status.success?
    refute_match(/\.rb:\d+:in /, stderr)
  end

  def test_export_without_args_does_not_raise_nomethoderror
    _stdout, stderr, status = Open3.capture3(A1_PATH, "-c", "export")
    refute status.success?
    refute_match(/NoMethodError|undefined method/, stderr)
  end

  def test_bg_without_command_reports_usage_error
    _stdout, stderr, status = Open3.capture3(A1_PATH, "-c", "bg")
    refute status.success?
    assert_match(/Usage: bg <command>/, stderr)
  end

  def test_rejects_empty_command_around_and_operator
    requires_extended_shell!("top-level && parsing")
    _stdout1, stderr1, status1 = Open3.capture3(A1_PATH, "-c", "&& echo hi")
    refute status1.success?
    assert_match(/syntax/i, stderr1)

    _stdout2, stderr2, status2 = Open3.capture3(A1_PATH, "-c", "echo hi &&")
    refute status2.success?
    assert_match(/syntax/i, stderr2)
  end

  #################################
  ### Execution and job control ###
  #################################

  def test_background_job
    output = `#{A1_PATH} -c 'bg echo hello'`.gsub(/\e\[([;\d]+)?m/, "")
    pid = /\(pid (\d+)\)/.match(output)[1]
    lines = output.split("\n").map(&:chomp)
    assert_equal ["Running job 1 (pid #{pid}) in background", "hello"], lines.sort
  end

  def test_resolves_executables_with_absolute_paths
    output = `#{A1_PATH} -c '/usr/bin/which -a which'`.lines.map(&:chomp)
    assert_includes output, "/usr/bin/which"
  end

  def test_resolves_executables_with_relative_paths
    File.write("test_bin/something", TRIVIAL_SHELL_SCRIPT)
    File.chmod(0o755, "test_bin/something")
    assert system("#{A1_PATH} -c ./test_bin/something")
  end

  def test_resolves_executables_in_absolute_paths
    output = `#{A1_PATH} -c 'which -a which'`.lines.map(&:chomp)
    assert_includes output, "/usr/bin/which"
  end

  def test_resolves_executables_in_relative_paths
    code = rand(1_000_000).to_s
    File.write("test_bin/definitely_executable", unique_shell_script(code))
    File.chmod(0o755, "test_bin/definitely_executable")
    actual = `PATH="./test_bin:$PATH" #{A1_PATH} -c definitely_executable`.chomp
    assert_equal code, actual
  end

  def test_does_not_resolve_non_executable_files_in_path
    File.write("test_bin/definitely_not_executable", TRIVIAL_SHELL_SCRIPT)
    File.chmod(0o644, "test_bin/definitely_not_executable")
    actual = system("PATH=\"./test_bin:$PATH\" #{A1_PATH} -c definitely_not_executable 2>/dev/null")
    assert_equal false, actual
  end

  def test_refreshes_readline_after_bg_execution
    called = false
    job_control = Shell::JobControl.new(
      logger: Shell::Logger.instance,
      refresh_line: -> { called = true }
    )
    previous = job_control.trap_sigchld
    begin
      job_control.exec_command("echo", ["hello"], background: true)
      Timeout.timeout(2) do
        sleep 0.01 until called
      end
      assert called
    ensure
      Signal.trap("CHLD", previous)
    end
  end

  #########################
  ### Built-in commands ###
  #########################

  def test_builtin_cd_no_args
    requires_extended_shell!("multi-command sequencing with ;")
    assert_equal Dir.home, `#{A1_PATH} -c 'cd; echo $PWD'`.strip
  end

  def test_builtin_cd
    requires_extended_shell!("multi-command sequencing with ;")
    assert_equal File.join(Dir.pwd, "blah"), `#{A1_PATH} -c 'mkdir -p blah; cd blah; echo $PWD; cd ..; rm -rf blah'`.strip
  end

  def test_builtin_cd_dash
    requires_extended_shell!("multi-command sequencing with ;")
    assert_equal Dir.pwd, `#{A1_PATH} -c 'mkdir -p blah; cd blah; cd -; rm -rf blah; echo $PWD'`.strip
  end

  def test_builtin_cd_parent
    requires_extended_shell!("multi-command sequencing with ;")
    assert_equal Dir.pwd, `#{A1_PATH} -c 'mkdir -p blah; cd blah; cd ..; rm -rf blah; echo $PWD'`.strip
  end

  def test_builtin_pwd
    assert_equal Dir.pwd, `#{A1_PATH} -c pwd`.chomp

    shell_path = File.expand_path(A1_PATH, Dir.pwd)
    assert_equal "/usr/bin", `cd /usr/bin && '#{shell_path}' -c pwd`.chomp
  end
end
