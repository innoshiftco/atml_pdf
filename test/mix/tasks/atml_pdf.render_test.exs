defmodule Mix.Tasks.AtmlPdf.RenderTest do
  @moduledoc false
  use ExUnit.Case

  @minimal_xml ~s|<document width="100pt" height="100pt"></document>|

  @full_xml """
  <document width="400pt" height="200pt" font-family="Helvetica" font-size="8pt">
    <row height="fill">
      <col width="fill" vertical-align="center" text-align="center"
           font-size="14pt" font-weight="bold">
        AIR WAYBILL
      </col>
    </row>
  </document>
  """

  # Write a temporary template file and return its path.
  defp write_template(xml, suffix \\ ".xml") do
    path =
      Path.join(
        System.tmp_dir!(),
        "atml_task_test_#{:erlang.unique_integer([:positive])}#{suffix}"
      )

    File.write!(path, xml)
    path
  end

  # Run the task via Mix.Shell.Process so all shell output (info + error) is
  # delivered as messages to the current process rather than written to
  # stdout/stderr. Returns all messages joined as a single string.
  defp run_task(args) do
    Mix.shell(Mix.Shell.Process)

    try do
      Mix.Tasks.AtmlPdf.Render.run(args)
    catch
      :exit, {:shutdown, _} -> :ok
    end

    messages =
      Stream.repeatedly(fn ->
        receive do
          {:mix_shell, _, [msg]} -> msg
        after
          0 -> nil
        end
      end)
      |> Stream.take_while(&(&1 != nil))
      |> Enum.join("\n")

    Mix.shell(Mix.Shell.IO)
    messages
  end

  describe "Mix.Tasks.AtmlPdf.Render" do
    test "renders template to default output path (.pdf beside template)" do
      template = write_template(@minimal_xml)
      expected_output = Path.rootname(template) <> ".pdf"

      try do
        output = run_task([template])
        assert output =~ "Written:"
        assert output =~ expected_output
        assert File.exists?(expected_output)
        assert File.stat!(expected_output).size > 0
      after
        File.rm(template)
        File.rm(Path.rootname(template) <> ".pdf")
      end
    end

    test "renders template to an explicit output path" do
      template = write_template(@full_xml)

      output_path =
        Path.join(System.tmp_dir!(), "atml_explicit_#{:erlang.unique_integer([:positive])}.pdf")

      try do
        output = run_task([template, output_path])
        assert output =~ "Written:"
        assert output =~ output_path
        assert File.exists?(output_path)

        {:ok, binary} = File.read(output_path)
        assert binary =~ "%PDF-"
      after
        File.rm(template)
        File.rm(output_path)
      end
    end

    test "prints error when no arguments given" do
      output = run_task([])
      assert output =~ "Error:"
      assert output =~ "TEMPLATE"
    end

    test "prints error when template file does not exist" do
      output = run_task(["/nonexistent/path/template.xml"])
      assert output =~ "Error:"
      assert output =~ "cannot read"
    end

    test "prints error when template XML is malformed" do
      template = write_template("<not valid xml", ".xml")

      try do
        output = run_task([template])
        assert output =~ "Error:"
      after
        File.rm(template)
      end
    end

    test "ignores extra arguments beyond OUTPUT" do
      template = write_template(@minimal_xml)

      output_path =
        Path.join(System.tmp_dir!(), "atml_extra_#{:erlang.unique_integer([:positive])}.pdf")

      try do
        output = run_task([template, output_path, "--ignored", "extra"])
        assert output =~ "Written:"
        assert File.exists?(output_path)
      after
        File.rm(template)
        File.rm(output_path)
      end
    end
  end
end
