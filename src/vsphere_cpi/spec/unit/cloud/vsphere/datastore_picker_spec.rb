require 'spec_helper'

module VSphereCloud
  describe DatastorePicker do
    before do
      allow(Random).to receive(:rand).and_return(1)
    end

    describe '#best_disk_placement' do
      context 'when a single DS is available' do
        let(:ds_1) { instance_double(VSphereCloud::Resources::Datastore, free_space: 1024) }
        let(:available_datastores) do
         {
           'ds-1' => ds_1,
         }
        end
        let(:already_placed_disk) do
          instance_double(VSphereCloud::DiskConfig,
            size: 256,
            existing_datastore_name: 'ds-1',
            target_datastore_pattern: '.*',
          )
        end
        let(:moved_disk) do
          instance_double(VSphereCloud::DiskConfig,
            size: 512,
            existing_datastore_name: nil,
            target_datastore_pattern: '.*',
          )
        end

        it 'returns the only valid placement' do
          picker = DatastorePicker.new(0)
          picker.update(available_datastores)
          disks = [already_placed_disk, moved_disk]

          expect(picker.best_disk_placement(disks)).to include({
            datastores: {
              'ds-1' => {
                free_space: 1024 - 512,
                disks: disks,
              }
            }
          })
        end

        context 'when no valid placement exists' do
          let(:large_disk) do
            instance_double(VSphereCloud::DiskConfig,
              size: 999999,
              existing_datastore_name: nil,
              target_datastore_pattern: '.*',
            )
          end

          it 'raises an error' do
            picker = DatastorePicker.new(0)
            picker.update(available_datastores)
            disks = [large_disk]

            expect{
              picker.best_disk_placement(disks)
            }.to raise_error Bosh::Clouds::CloudError, /No valid placement/
          end
        end
      end

      context 'when multiple DSes are available' do
        let(:ds_1) { instance_double(VSphereCloud::Resources::Datastore, free_space: 512) }
        let(:ds_2) { instance_double(VSphereCloud::Resources::Datastore, free_space: 1024) }
        let(:available_datastores) do
         {
           'ds-1' => ds_1,
           'ds-2' => ds_2,
         }
        end
        let(:disk1) do
          instance_double(VSphereCloud::DiskConfig,
            size: 256,
            target_datastore_pattern: 'ds-2',
            existing_datastore_name: nil
          )
        end
        let(:disk2) do
          instance_double(VSphereCloud::DiskConfig,
            size: 512,
            target_datastore_pattern: '.*',
            existing_datastore_name: nil
          )
        end

        let(:picker) { DatastorePicker.new(0) }

        it 'places the disks into the datastores' do
          picker.update(available_datastores)

          disks = [disk1, disk2]
          expect(picker.best_disk_placement(disks)).to include({
            datastores: {
              'ds-1' => {
                free_space: 512,
                disks: [],
              },
              'ds-2' => {
                free_space: 256,
                disks: [disk1, disk2],
              },
            }
          })
        end

        context 'when headroom is not specified' do
          let(:ds_1) { instance_double(VSphereCloud::Resources::Datastore, free_space: 1536) }
          let(:ds_2) { instance_double(VSphereCloud::Resources::Datastore, free_space: 2048) }
          let(:available_datastores) do
           {
             'ds-1' => ds_1,
             'ds-2' => ds_2,
           }
          end
          let(:disk1) do
            instance_double(VSphereCloud::DiskConfig,
              size: 256,
              target_datastore_pattern: 'ds-2',
              existing_datastore_name: nil
            )
          end
          let(:disk2) do
            instance_double(VSphereCloud::DiskConfig,
              size: 512,
              target_datastore_pattern: '.*',
              existing_datastore_name: nil
            )
          end

          it 'defaults headroom to 1024' do
            picker = DatastorePicker.new
            picker.update(available_datastores)

            disks = [disk1, disk2]
            expect(picker.best_disk_placement(disks)).to include({
              datastores: {
                'ds-1' => {
                  free_space: 0,
                  disks: [disk2],
                },
                'ds-2' => {
                  free_space: 768,
                  disks: [disk1],
                },
              }
            })
          end
        end

        context 'when headroom is specified' do
          let(:headroom) { 512}
          let(:ds_1) { instance_double(VSphereCloud::Resources::Datastore, free_space: 1536) }
          let(:ds_2) { instance_double(VSphereCloud::Resources::Datastore, free_space: 2048) }
          let(:available_datastores) do
           {
             'ds-1' => ds_1,
             'ds-2' => ds_2,
           }
          end
          let(:disk1) do
            instance_double(VSphereCloud::DiskConfig,
              size: 256,
              target_datastore_pattern: 'ds-2',
              existing_datastore_name: nil
            )
          end
          let(:disk2) do
            instance_double(VSphereCloud::DiskConfig,
              size: 512,
              target_datastore_pattern: '.*',
              existing_datastore_name: nil
            )
          end

          it 'accounts for additional headroom' do
            picker = DatastorePicker.new(headroom)
            picker.update(available_datastores)

            disks = [disk1, disk2]
            expect(picker.best_disk_placement(disks)).to include({
              datastores: {
                'ds-1' => {
                  free_space: 512,
                  disks: [disk2],
                },
                'ds-2' => {
                  free_space: 1280,
                  disks: [disk1],
                },
              }
            })
          end
        end

        context 'when given existing_datastore_name' do
          let(:disk1) do
            instance_double(VSphereCloud::DiskConfig,
              size: 256,
              existing_datastore_name: 'ds-2',
              target_datastore_pattern: '.*',
            )
          end
          let(:disk2) do
            instance_double(VSphereCloud::DiskConfig,
              size: 512,
              target_datastore_pattern: '.*',
              existing_datastore_name: nil
            )
          end

          it 'keeps the disk in its existing datastore to minimize disk migrations' do
            picker = DatastorePicker.new(0)
            picker.update(available_datastores)
            disks = [disk1, disk2]
            expect(picker.best_disk_placement(disks)).to include({
              datastores: {
                'ds-1' => {
                  free_space: 512,
                  disks: [],
                },
                'ds-2' => {
                  free_space: 512,
                  disks: [disk1, disk2],
                },
              }
            })
          end
        end

        context 'when given existing_datastore_name that is not available' do
          let(:disk1) do
            instance_double(VSphereCloud::DiskConfig,
              size: 256,
              existing_datastore_name: 'non-accessible-ds',
              target_datastore_pattern: '.*',
            )
          end
          let(:disk2) do
            instance_double(VSphereCloud::DiskConfig,
              size: 512,
              target_datastore_pattern: '.*',
              existing_datastore_name: nil
            )
          end

          it 'places the disk in an available datastore and includes the migration size' do
            picker = DatastorePicker.new(0)
            picker.update(available_datastores)

            disks = [disk1, disk2]

            expect(picker.best_disk_placement(disks)).to include({
              migration_size: 256,
              datastores: {
                'ds-1' => {
                  disks: [],
                  free_space: 512,
                },
                'ds-2' => {
                  disks: [disk1, disk2],
                  free_space: 256,
                },
              },
            })
          end
        end

        describe ':balance_score' do
          it 'is calculated from (min + mean + median) free disk space, to balance things nicely' do
            [
              { datastore_space: [5,    5,    5],   balance_score: 15 },
              { datastore_space: [2000, 1,    1],   balance_score: 669 },
              { datastore_space: [100,  1000, 200], balance_score: 733 },
              { datastore_space: [500,  500,  400], balance_score: 1366 },
              { datastore_space: [700,  700],       balance_score: 2100 },
            ].each do |input|
              available_datastores = input[:datastore_space].each_with_index.map do |free_space, index|
                [ "ds-#{index}", instance_double(VSphereCloud::Resources::Datastore, free_space: free_space) ]
              end.to_h

              picker = DatastorePicker.new(0)
              picker.update(available_datastores)

              expect(picker.best_disk_placement([])[:balance_score]).to eq(input[:balance_score])
            end
          end
        end
      end

      context 'simulating placement distribution of several datastores' do
        let(:datastore_1) { instance_double(VSphereCloud::Resources::Datastore, free_space: 51200) }
        let(:datastore_2) { instance_double(VSphereCloud::Resources::Datastore, free_space: 10240) }
        let(:datastore_3) { instance_double(VSphereCloud::Resources::Datastore, free_space: 20480) }
        let(:datastore_4) { instance_double(VSphereCloud::Resources::Datastore, free_space: 10240) }
        let(:available_datastores) do
          {
            'datastore-1' => datastore_1,
            'datastore-2' => datastore_2,
            'datastore-3' => datastore_3,
            'datastore-4' => datastore_4
          }
        end
        let(:disk1) do
          instance_double(VSphereCloud::DiskConfig,
            size: 256,
            target_datastore_pattern: '.*',
            existing_datastore_name: nil
          )
        end
        let(:disk2) do
          instance_double(VSphereCloud::DiskConfig,
            size: 512,
            target_datastore_pattern: '.*',
            existing_datastore_name: nil
          )
        end
        let(:disk3) do
          instance_double(VSphereCloud::DiskConfig,
            size: 512,
            target_datastore_pattern: '.*',
            existing_datastore_name: nil
          )
        end
        let(:disk4) do
          instance_double(VSphereCloud::DiskConfig,
            size: 1024,
            target_datastore_pattern: '.*',
            existing_datastore_name: nil
          )
        end

        it 'simulates placement' do
          picker = DatastorePicker.new(0)
          picker.update(available_datastores)
          disks = [disk1, disk2, disk3, disk4]
          allow(Random).to receive(:rand).and_call_original
          'ds-1 => [disk1, disk2]'
          disk_counts_hash = {}
          100.times do
            picker.best_disk_placement(disks)[:datastores].each do |ds_name, ds_props|
              disk_counts_hash[ds_name] ||= 0
              disk_counts_hash[ds_name] += ds_props[:disks].length
            end
          end
          sorted_datastores = available_datastores.sort do |x, y|
            y[1].free_space <=> x[1].free_space
          end
          puts 'Summary of simulated placements'
          sorted_datastores.each do |ds|
            print "#{ds[0]}: free_space => #{ds[1].free_space}, disk_counts => #{disk_counts_hash[ds[0]]}\n"
          end
        end
      end
    end

    describe '#pick_datastore_for_single_disk' do
      let(:smaller_ds) { instance_double(VSphereCloud::Resources::Datastore, free_space: 256) }
      let(:larger_ds) { instance_double(VSphereCloud::Resources::Datastore, free_space: 1024) }
      let(:available_datastores) do
       {
         'smaller-ds' => smaller_ds,
         'larger-ds' => larger_ds,
       }
      end
      let(:disk) do
        instance_double(VSphereCloud::DiskConfig,
          size: 512,
          target_datastore_pattern: '.*',
          existing_datastore_name: nil
        )
      end

      it 'returns the picked datastore name' do
        picker = DatastorePicker.new(0)
        picker.update(available_datastores)

        expect(picker.pick_datastore_for_single_disk(disk)).to eq('larger-ds')
      end
    end
  end
end
