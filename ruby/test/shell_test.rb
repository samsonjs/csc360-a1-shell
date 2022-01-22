require 'minitest/autorun'

class ShellTest < Minitest::Test
  TRIVIAL_SHELL_SCRIPT = "#!/bin/sh\ntrue".freeze

  A1_PATH = './a1'.freeze

  def setup
    FileUtils.mkdir_p('test_bin')
  end

  def teardown
    FileUtils.rm_rf('test_bin')
  end

  def unique_shell_script(code)
    "#!/bin/sh\necho '#{code}'"
  end

  def test_expands_environment_variables
    assert_equal ENV['HOME'], `#{A1_PATH} -c 'echo $HOME'`.chomp
    assert system("#{A1_PATH} -c 'echo $HOME' >/dev/null")
  end

  def test_fails_on_unknown_variables
    assert_equal false, system("#{A1_PATH} -c 'echo $DEFINITELY_DOES_NOT_EXIST' 2>/dev/null")
  end

  #################################
  ### Execution and job control ###
  #################################

  def test_background_job
    output = `#{A1_PATH} -c 'bg echo hello'`
    assert output.match?(/\ABackground job 1 \(pid \d+\)\nhello\n\z/m), "'#{output}' is unexpected"
  end

  def test_resolves_executables_with_absolute_paths
    assert_equal '/usr/bin/which', `#{A1_PATH} -c '/usr/bin/which -a which'`.chomp
  end

  def test_resolves_executables_with_relative_paths
    File.write('test_bin/something', TRIVIAL_SHELL_SCRIPT)
    File.chmod(0o755, 'test_bin/something')
    assert system("#{A1_PATH} -c ./test_bin/something")
  end

  def test_resolves_executables_in_absolute_paths
    assert_equal '/usr/bin/which', `#{A1_PATH} -c 'which -a which'`.chomp
  end

  def test_resolves_executables_in_relative_paths
    code = rand(1_000_000).to_s
    File.write('test_bin/definitely_executable', unique_shell_script(code))
    File.chmod(0o755, 'test_bin/definitely_executable')
    actual = `PATH="./test_bin:$PATH" #{A1_PATH} -c definitely_executable`.chomp
    assert_equal code, actual
  end

  def test_does_not_resolve_non_executable_files_in_path
    File.write('test_bin/definitely_not_executable', TRIVIAL_SHELL_SCRIPT)
    File.chmod(0o644, 'test_bin/definitely_not_executable')
    actual = system("PATH=\"./test_bin:$PATH\" #{A1_PATH} -c definitely_not_executable 2>/dev/null")
    assert_equal false, actual
  end

  def test_refreshes_readline_after_bg_execution
    skip 'unimplemented'
  end

  #########################
  ### Built-in commands ###
  #########################

  def test_builtin_cd_no_args
    skip 'cannot easily implement without sequencing with ; or &&'
  end

  def test_builtin_cd
    skip 'cannot easily implement without sequencing with ; or &&'
  end

  def test_builtin_cd_dash
    skip 'cannot easily implement without sequencing with ; or &&'
  end

  def test_builtin_cd_parent
    skip 'cannot easily implement without sequencing with ; or &&'
  end

  def test_builtin_pwd
    assert_equal Dir.pwd, `#{A1_PATH} -c pwd`.chomp

    shell_path = File.expand_path(A1_PATH, Dir.pwd)
    assert_equal '/usr/bin', `cd /usr/bin && '#{shell_path}' -c pwd`.chomp
  end
end
