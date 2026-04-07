# frozen_string_literal: true

require "spec_helper"
require "tech_debt/collectors/flay_collector"

RSpec.describe TechDebt::Collectors::FlayCollector do
  let(:config) do
    instance_double(
      TechDebt::Config,
      analysis: { "paths" => [], "exclude_paths" => [] },
      flay_threshold: 25
    )
  end

  subject(:collector) { described_class.new(config, files: files) }

  # Returns a collector with an explicit file list so we bypass glob expansion.
  let(:files) { ["app/models/order.rb", "app/models/invoice.rb"] }

  describe "#call" do
    context "when flay finds no output" do
      before do
        allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true, exitstatus: 0)])
      end

      it "returns an empty array" do
        expect(collector.call).to eq([])
      end
    end

    context "when the file list is empty" do
      let(:files) { [] }

      it "returns an empty array without calling flay" do
        expect(Open3).not_to receive(:capture3)
        expect(collector.call).to eq([])
      end
    end

    context "with IDENTICAL duplication group" do
      let(:flay_output) do
        <<~OUTPUT
          Total score (lower is better) = 340

          1) IDENTICAL code found in :defn (mass*2 = 340)
            app/models/order.rb:10
            app/models/invoice.rb:20

        OUTPUT
      end

      before do
        allow(Open3).to receive(:capture3).and_return([flay_output, "", double(success?: true, exitstatus: 0)])
        allow(File).to receive(:expand_path).and_wrap_original { |m, p| m.call(p) }
      end

      it "emits one candidate per in-scope file" do
        results = collector.call
        expect(results.size).to eq(2)
      end

      it "sets type to structural_duplication" do
        expect(collector.call.map { |c| c[:type] }.uniq).to eq(["structural_duplication"])
      end

      it "uses the flay mass (not the multiplied score) as the score" do
        # mass*2 = 340 means base mass is 170
        expect(collector.call.map { |c| c[:score] }.uniq).to eq([170.0])
      end

      it "includes the peer file reference in the detail" do
        order_candidate = collector.call.find { |c| c[:file] == "app/models/order.rb" }
        expect(order_candidate[:detail]).to include("app/models/invoice.rb:20")
      end

      it "includes IDENTICAL in the detail" do
        expect(collector.call.first[:detail]).to include("IDENTICAL")
      end
    end

    context "with Similar duplication group" do
      let(:flay_output) do
        <<~OUTPUT
          Total score (lower is better) = 184

          1) Similar code found in :defn (mass = 184)
            A: app/models/order.rb:10
            B: app/models/invoice.rb:20

        OUTPUT
      end

      before do
        allow(Open3).to receive(:capture3).and_return([flay_output, "", double(success?: true, exitstatus: 0)])
      end

      it "emits candidates for both files" do
        expect(collector.call.size).to eq(2)
      end

      it "uses the raw mass as the score" do
        expect(collector.call.map { |c| c[:score] }.uniq).to eq([184.0])
      end

      it "includes Similar in the detail" do
        expect(collector.call.first[:detail]).to include("Similar")
      end
    end

    context "when a group references files outside the target set" do
      let(:flay_output) do
        <<~OUTPUT
          Total score (lower is better) = 100

          1) IDENTICAL code found in :defn (mass = 100)
            app/models/order.rb:10
            vendor/some_lib.rb:5

        OUTPUT
      end

      let(:files) { ["app/models/order.rb"] }

      before do
        allow(Open3).to receive(:capture3).and_return([flay_output, "", double(success?: true, exitstatus: 0)])
      end

      it "only emits candidates for in-scope files" do
        results = collector.call
        expect(results.map { |c| c[:file] }).to eq(["app/models/order.rb"])
      end

      it "still includes the out-of-scope peer in the detail" do
        expect(collector.call.first[:detail]).to include("vendor/some_lib.rb")
      end
    end

    context "when all files in a group are out of scope" do
      let(:flay_output) do
        <<~OUTPUT
          Total score (lower is better) = 100

          1) IDENTICAL code found in :defn (mass = 100)
            vendor/a.rb:1
            vendor/b.rb:2

        OUTPUT
      end

      before do
        allow(Open3).to receive(:capture3).and_return([flay_output, "", double(success?: true, exitstatus: 0)])
      end

      it "emits no candidates" do
        expect(collector.call).to be_empty
      end
    end

    context "with multiple groups" do
      let(:flay_output) do
        <<~OUTPUT
          Total score (lower is better) = 500

          1) IDENTICAL code found in :defn (mass*2 = 340)
            app/models/order.rb:10
            app/models/invoice.rb:20

          2) Similar code found in :if (mass = 160)
            app/models/order.rb:50
            app/models/invoice.rb:80

        OUTPUT
      end

      before do
        allow(Open3).to receive(:capture3).and_return([flay_output, "", double(success?: true, exitstatus: 0)])
      end

      it "emits candidates from all groups" do
        expect(collector.call.size).to eq(4)
      end
    end

    context "when flay exits non-zero" do
      before do
        allow(Open3).to receive(:capture3).and_return(
          ["some output\n\n1) Similar code found in :defn (mass = 50)\n  app/models/order.rb:1\n  app/models/invoice.rb:2\n",
           "",
           double(success?: false, exitstatus: 1)]
        )
      end

      it "warns about non-zero exit" do
        expect { collector.call }.to output(/Flay exited non-zero: 1/).to_stderr
      end

      it "still returns parsed candidates" do
        expect(collector.call).not_to be_empty
      end
    end
  end
end
