#!/bin/bash
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

PANEL_DIR="/var/www/pterodactyl"
BACKUP_DIR="/root/protect-backup-$(date +%Y%m%d-%H%M%S)"

if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}❌ Jalankan sebagai root${NC}"
  exit 1
fi

if [ ! -d "$PANEL_DIR" ]; then
  echo -e "${RED}❌ Panel tidak ditemukan di $PANEL_DIR${NC}"
  exit 1
fi

mkdir -p "$BACKUP_DIR"

echo -e "${CYAN}${BOLD}========================================${NC}"
echo -e "${MAGENTA}${BOLD}   🛡️  NDY PROTECT INSTALLER v1.5${NC}"
echo -e "${CYAN}${BOLD}========================================${NC}"
echo -e "${CYAN}┌ 📁 Panel    : ${YELLOW}${PANEL_DIR}${NC}"
echo -e "${CYAN}├ 💾 Backup   : ${YELLOW}${BACKUP_DIR}${NC}"
echo -e "${CYAN}└ ⏱️  Start    : ${YELLOW}$(date '+%H:%M:%S')${NC}"
echo -e "${CYAN}${BOLD}========================================${NC}"
echo ""

SUKSES=0
GAGAL=0

install_file() {
  local NAME="$1"
  local PATH_TARGET="$2"
  local CONTENT_FILE="$3"

  local DIR_TARGET
  DIR_TARGET="$(dirname "$PATH_TARGET")"

  if [ ! -d "$DIR_TARGET" ]; then
    echo -e "${RED}❌ Folder tidak ada: ${DIR_TARGET}${NC}"
    GAGAL=$((GAGAL + 1))
    return 1
  fi

  if [ -f "$PATH_TARGET" ]; then
    local REL
    REL="${PATH_TARGET#/}"
    local BACKUP_PATH="${BACKUP_DIR}/${REL}"
    mkdir -p "$(dirname "$BACKUP_PATH")"
    cp -a "$PATH_TARGET" "$BACKUP_PATH"
    echo -e "${CYAN}   💾 Backup: ${REL}${NC}"
  fi

  cp -f "$CONTENT_FILE" "$PATH_TARGET"

  chown www-data:www-data "$PATH_TARGET" 2>/dev/null || true
  chmod 644 "$PATH_TARGET"

  echo -e "${GREEN}   ✅ Terpasang: ${NAME}${NC}"
  SUKSES=$((SUKSES + 1))
  return 0
}

write_content() {
  local TARGET="$1"
  local TMPFILE
  TMPFILE="$(mktemp)"
  cat > "$TMPFILE"
  echo "$TMPFILE"
}

# ========================================================
# 1. ServerController.php
# ========================================================
echo -e "${YELLOW}▶️  [1] ServerController.php${NC}"

TMP1="$(write_content <<'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Servers;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Nest;
use Pterodactyl\Models\Location;
use Spatie\QueryBuilder\QueryBuilder;
use Spatie\QueryBuilder\AllowedFilter;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Models\Filters\AdminServerFilter;
use Illuminate\Contracts\View\Factory as ViewFactory;

class ServerController extends Controller
{
    public function __construct(private ViewFactory $view)
    {
    }

    public function index(Request $request): View
    {
        $user = Auth::user();

        $query = Server::query()
            ->with(['node', 'user', 'allocation'])
            ->orderBy('id', 'asc');

        if ($user->id !== 1) {
            $query->where('owner_id', $user->id);
        }

        $servers = QueryBuilder::for($query)
            ->allowedFilters([
                AllowedFilter::exact('owner_id'),
                AllowedFilter::custom('*', new AdminServerFilter()),
            ])
            ->when($request->has('filter') && isset($request->filter['search']), function ($q) use ($request) {
                $search = $request->filter['search'];
                $q->where(function ($sub) use ($search) {
                    $sub->where('name', 'like', "%{$search}%")
                        ->orWhere('uuidShort', 'like', "%{$search}%")
                        ->orWhere('uuid', 'like', "%{$search}%");
                });
            })
            ->paginate(config('pterodactyl.paginate.admin.servers'))
            ->appends($request->query());

        return $this->view->make('admin.servers.index', ['servers' => $servers]);
    }

    public function create(): View
    {
        $user = Auth::user();

        if ($user->id === 1) {
            $users = User::all();
            $lock_owner = false;
            $auto_owner = null;
        } else {
            $users = collect([$user]);
            $lock_owner = true;
            $auto_owner = $user;
        }

        return $this->view->make('admin.servers.new', [
            'users' => $users,
            'lock_owner' => $lock_owner,
            'auto_owner' => $auto_owner,
            'locations' => Location::with('nodes')->get(),
            'nests' => Nest::with('eggs')->get(),
        ]);
    }

    public function view(Server $server): View
    {
        $user = Auth::user();

        if ($user->id !== 1 && $server->owner_id !== $user->id) {
            abort(403, '🚫 Akses ditolak: Hanya admin ID 1 yang dapat melihat atau mengedit server ini.');
        }

        return $this->view->make('admin.servers.view', ['server' => $server]);
    }

    public function update(Request $request, Server $server)
    {
        $user = Auth::user();

        if ($user->id !== 1 && $server->owner_id !== $user->id) {
            abort(403, '🚫 Akses ditolak: Hanya admin ID 1 yang dapat mengubah server ini.');
        }

        $data = $request->except(['owner_id']);

        $server->update($data);

        return redirect()->route('admin.servers.view', $server->id)
            ->with('success', '✅ Server berhasil diperbarui.');
    }

    public function destroy(Server $server)
    {
        $user = Auth::user();

        if ($user->id !== 1) {
            abort(403, '🚫 Akses ditolak: Hanya admin ID 1 yang dapat menghapus server ini.');
        }

        $server->delete();

        return redirect()->route('admin.servers')
            ->with('success', '🗑️ Server berhasil dihapus.');
    }
}
PHPEOF
)"

install_file \
  "PROTECT1 — Anti Intip Server In Settings" \
  "/var/www/pterodactyl/app/Http/Controllers/Admin/Servers/ServerController.php" \
  "$TMP1"
rm -f "$TMP1"

# ========================================================
# 2. new.blade.php
# ========================================================
echo -e "${YELLOW}▶️  [2] new.blade.php${NC}"

TMP2="$(mktemp)"
cat > "$TMP2" <<'BLADE_EOF'
@extends('layouts.admin')

@section('title')
    New Server
@endsection

@section('content-header')
    <h1>Create Server<small>Add a new server to the panel.</small></h1>
    <ol class="breadcrumb">
        <li><a href="{{ route('admin.index') }}">Admin</a></li>
        <li><a href="{{ route('admin.servers') }}">Servers</a></li>
        <li class="active">Create Server</li>
    </ol>
@endsection

@section('content')
<form action="{{ route('admin.servers.new') }}" method="POST">
    <div class="row">
        <div class="col-xs-12">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Core Details</h3>
                </div>

                <div class="box-body row">
                    <div class="col-md-6">
                        <div class="form-group">
                            <label for="pName">Server Name</label>
                            <input type="text" class="form-control" id="pName" name="name" value="{{ old('name') }}" placeholder="Server Name">
                            <p class="small text-muted no-margin">Character limits: <code>a-z A-Z 0-9 _ - .</code> and <code>[Space]</code>.</p>
                        </div>

                        <div class="form-group">
                            <label for="pUserId">Server Owner</label>
                            @if(Auth::user()->id == 1)
                                <select id="pUserId" name="owner_id" class="form-control">
                                    <option value="">Select a User</option>
                                    @foreach(\Pterodactyl\Models\User::all() as $user)
                                        <option value="{{ $user->id }}" @selected(old('owner_id') == $user->id)>
                                            {{ $user->username }} ({{ $user->email }})
                                        </option>
                                    @endforeach
                                </select>
                                <p class="small text-muted no-margin">As admin, you can manually choose the server owner.</p>
                            @else
                                <input type="hidden" id="pUserId" name="owner_id" value="{{ Auth::user()->id }}">
                                <input type="text" class="form-control" value="{{ Auth::user()->email }}" disabled>
                                <p class="small text-muted no-margin">This server will be owned by your account automatically.</p>
                            @endif
                        </div>
                    </div>

                    <div class="col-md-6">
                        <div class="form-group">
                            <label for="pDescription" class="control-label">Server Description</label>
                            <textarea id="pDescription" name="description" rows="3" class="form-control">{{ old('description') }}</textarea>
                            <p class="text-muted small">A brief description of this server.</p>
                        </div>

                        <div class="form-group">
                            <div class="checkbox checkbox-primary no-margin-bottom">
                                <input id="pStartOnCreation" name="start_on_completion" type="checkbox" {{ \Pterodactyl\Helpers\Utilities::checked('start_on_completion', 1) }} />
                                <label for="pStartOnCreation" class="strong">Start Server when Installed</label>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-xs-12">
            <div class="box">
                <div class="overlay" id="allocationLoader" style="display:none;"><i class="fa fa-refresh fa-spin"></i></div>
                <div class="box-header with-border">
                    <h3 class="box-title">Allocation Management</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-sm-4">
                        <label for="pNodeId">Node</label>
                        <select name="node_id" id="pNodeId" class="form-control">
                            @foreach($locations as $location)
                                <optgroup label="{{ $location->long }} ({{ $location->short }})">
                                @foreach($location->nodes as $node)
                                <option value="{{ $node->id }}"
                                    @if($location->id === old('location_id')) selected @endif
                                >{{ $node->name }}</option>
                                @endforeach
                                </optgroup>
                            @endforeach
                        </select>
                        <p class="small text-muted no-margin">The node which this server will be deployed to.</p>
                    </div>

                    <div class="form-group col-sm-4">
                        <label for="pAllocation">Default Allocation</label>
                        <select id="pAllocation" name="allocation_id" class="form-control"></select>
                        <p class="small text-muted no-margin">The main allocation that will be assigned to this server.</p>
                    </div>

                    <div class="form-group col-sm-4">
                        <label for="pAllocationAdditional">Additional Allocation(s)</label>
                        <select id="pAllocationAdditional" name="allocation_additional[]" class="form-control" multiple></select>
                        <p class="small text-muted no-margin">Additional allocations to assign to this server on creation.</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-xs-12">
            <div class="box">
                <div class="overlay" id="allocationLoader" style="display:none;"><i class="fa fa-refresh fa-spin"></i></div>
                <div class="box-header with-border">
                    <h3 class="box-title">Application Feature Limits</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-6">
                        <label for="pDatabaseLimit" class="control-label">Database Limit</label>
                        <div>
                            <input type="text" id="pDatabaseLimit" name="database_limit" class="form-control" value="{{ old('database_limit', 0) }}"/>
                        </div>
                    </div>
                    <div class="form-group col-xs-6">
                        <label for="pAllocationLimit" class="control-label">Allocation Limit</label>
                        <div>
                            <input type="text" id="pAllocationLimit" name="allocation_limit" class="form-control" value="{{ old('allocation_limit', 0) }}"/>
                        </div>
                    </div>
                    <div class="form-group col-xs-6">
                        <label for="pBackupLimit" class="control-label">Backup Limit</label>
                        <div>
                            <input type="text" id="pBackupLimit" name="backup_limit" class="form-control" value="{{ old('backup_limit', 0) }}"/>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div class="row">
        <div class="col-xs-12">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Resource Management</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-6">
                        <label for="pCPU">CPU Limit</label>
                        <div class="input-group">
                            <input type="text" id="pCPU" name="cpu" class="form-control" value="{{ old('cpu', 0) }}" />
                            <span class="input-group-addon">%</span>
                        </div>
                    </div>
                    <div class="form-group col-xs-6">
                        <label for="pThreads">CPU Pinning</label>
                        <div>
                            <input type="text" id="pThreads" name="threads" class="form-control" value="{{ old('threads') }}" />
                        </div>
                    </div>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-6">
                        <label for="pMemory">Memory</label>
                        <div class="input-group">
                            <input type="text" id="pMemory" name="memory" class="form-control" value="{{ old('memory') }}" />
                            <span class="input-group-addon">MiB</span>
                        </div>
                    </div>
                    <div class="form-group col-xs-6">
                        <label for="pSwap">Swap</label>
                        <div class="input-group">
                            <input type="text" id="pSwap" name="swap" class="form-control" value="{{ old('swap', 0) }}" />
                            <span class="input-group-addon">MiB</span>
                        </div>
                    </div>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-6">
                        <label for="pDisk">Disk Space</label>
                        <div class="input-group">
                            <input type="text" id="pDisk" name="disk" class="form-control" value="{{ old('disk') }}" />
                            <span class="input-group-addon">MiB</span>
                        </div>
                    </div>
                    <div class="form-group col-xs-6">
                        <label for="pIO">Block IO Weight</label>
                        <div>
                            <input type="text" id="pIO" name="io" class="form-control" value="{{ old('io', 500) }}" />
                        </div>
                    </div>
                    <div class="form-group col-xs-12">
                        <div class="checkbox checkbox-primary no-margin-bottom">
                            <input type="checkbox" id="pOomDisabled" name="oom_disabled" value="0" {{ \Pterodactyl\Helpers\Utilities::checked('oom_disabled', 0) }} />
                            <label for="pOomDisabled" class="strong">Enable OOM Killer</label>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-md-6">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Nest Configuration</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-12">
                        <label for="pNestId">Nest</label>
                        <select id="pNestId" name="nest_id" class="form-control">
                            @foreach($nests as $nest)
                                <option value="{{ $nest->id }}"
                                    @if($nest->id === old('nest_id'))
                                        selected="selected"
                                    @endif
                                >{{ $nest->name }}</option>
                            @endforeach
                        </select>
                    </div>

                    <div class="form-group col-xs-12">
                        <label for="pEggId">Egg</label>
                        <select id="pEggId" name="egg_id" class="form-control"></select>
                    </div>
                    <div class="form-group col-xs-12">
                        <div class="checkbox checkbox-primary no-margin-bottom">
                            <input type="checkbox" id="pSkipScripting" name="skip_scripts" value="1" {{ \Pterodactyl\Helpers\Utilities::checked('skip_scripts', 0) }} />
                            <label for="pSkipScripting" class="strong">Skip Egg Install Script</label>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div class="col-md-6">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Docker Configuration</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-12">
                        <label for="pDefaultContainer">Docker Image</label>
                        <select id="pDefaultContainer" name="image" class="form-control"></select>
                        <input id="pDefaultContainerCustom" name="custom_image" value="{{ old('custom_image') }}" class="form-control" placeholder="Or enter a custom image..." style="margin-top:1rem"/>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-md-12">
            <div class="box">
                <div class="box-header with-border">
                    <h3 class="box-title">Startup Configuration</h3>
                </div>

                <div class="box-body row">
                    <div class="form-group col-xs-12">
                        <label for="pStartup">Startup Command</label>
                        <input type="text" id="pStartup" name="startup" value="{{ old('startup') }}" class="form-control" />
                    </div>
                </div>

                <div class="box-header with-border" style="margin-top:-10px;">
                    <h3 class="box-title">Service Variables</h3>
                </div>

                <div class="box-body row" id="appendVariablesTo"></div>

                <div class="box-footer">
                    {!! csrf_field() !!}
                    <input type="submit" class="btn btn-success pull-right" value="Create Server" />
                </div>
            </div>
        </div>
    </div>
</form>
@endsection

@section('footer-scripts')
    @parent
    {!! Theme::js('vendor/lodash/lodash.js') !!}

    <script type="application/javascript">
        function serviceVariablesUpdated(eggId, ids) {
            @if (old('egg_id'))
                if (eggId != '{{ old('egg_id') }}') {
                    return;
                }
                @if (old('environment'))
                    @foreach (old('environment') as $key => $value)
                        $('#' + ids['{{ $key }}']).val('{{ $value }}');
                    @endforeach
                @endif
            @endif
            @if(old('image'))
                $('#pDefaultContainer').val('{{ old('image') }}');
            @endif
        }
    </script>

    {!! Theme::js('js/admin/new-server.js?v=20220530') !!}

    <script type="application/javascript">
        $(document).ready(function() {
            @if (old('node_id'))
                $('#pNodeId').val('{{ old('node_id') }}').change();
                @if (old('allocation_id'))
                    $('#pAllocation').val('{{ old('allocation_id') }}').change();
                @endif
                @if (old('allocation_additional'))
                    const additional_allocations = [];
                    @for ($i = 0; $i < count(old('allocation_additional')); $i++)
                        additional_allocations.push('{{ old('allocation_additional.'.$i)}}');
                    @endfor
                    $('#pAllocationAdditional').val(additional_allocations).change();
                @endif
            @endif

            @if (old('nest_id'))
                $('#pNestId').val('{{ old('nest_id') }}').change();
                @if (old('egg_id'))
                    $('#pEggId').val('{{ old('egg_id') }}').change();
                @endif
            @endif
        });
    </script>
@endsection
BLADE_EOF

install_file \
  "PROTECT1 — Otomatis Isi Server Owner" \
  "/var/www/pterodactyl/resources/views/admin/servers/new.blade.php" \
  "$TMP2"
rm -f "$TMP2"

# ========================================================
# 3. DetailsModificationService.php
# ========================================================
echo -e "${YELLOW}▶️  [3] DetailsModificationService.php${NC}"

TMP3="$(mktemp)"
cat > "$TMP3" <<'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Traits\Services\ReturnsUpdatedModels;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class DetailsModificationService
{
    use ReturnsUpdatedModels;

    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $serverRepository
    ) {
    }

    public function handle(Server $server, array $data): Server
    {
        $user = Auth::user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id ?? null;

            if ($ownerId !== $user->id) {
                throw new DisplayException(
                    '🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mengubah detail server milik orang lain.'
                );
            }
        }

        return $this->connection->transaction(function () use ($data, $server) {
            $owner = $server->owner_id;

            $server->forceFill([
                'external_id' => Arr::get($data, 'external_id'),
                'owner_id' => Arr::get($data, 'owner_id'),
                'name' => Arr::get($data, 'name'),
                'description' => Arr::get($data, 'description') ?? '',
            ])->saveOrFail();

            if ($server->owner_id !== $owner) {
                try {
                    $this->serverRepository->setServer($server)->revokeUserJTI($owner);
                } catch (DaemonConnectionException $exception) {
                }
            }

            return $server;
        });
    }
}
PHPEOF

install_file \
  "PROTECT1 — Anti Update Detail Server" \
  "/var/www/pterodactyl/app/Services/Servers/DetailsModificationService.php" \
  "$TMP3"
rm -f "$TMP3"

# ========================================================
# 4. BuildModificationService.php
# ========================================================
echo -e "${YELLOW}▶️  [4] BuildModificationService.php${NC}"

TMP4="$(mktemp)"
cat > "$TMP4" <<'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Allocation;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Support\Facades\Auth;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class BuildModificationService
{
    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository,
        private ServerConfigurationStructureService $structureService
    ) {
    }

    public function handle(Server $server, array $data): Server
    {
        $user = Auth::user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id ?? null;

            if ($ownerId !== $user->id) {
                throw new DisplayException(
                    '🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mengubah Build Configuration server orang lain.'
                );
            }
        }

        $server = $this->connection->transaction(function () use ($server, $data) {
            $this->processAllocations($server, $data);

            if (isset($data['allocation_id']) && $data['allocation_id'] != $server->allocation_id) {
                try {
                    Allocation::query()
                        ->where('id', $data['allocation_id'])
                        ->where('server_id', $server->id)
                        ->firstOrFail();
                } catch (ModelNotFoundException) {
                    throw new DisplayException('The requested default allocation is not currently assigned to this server.');
                }
            }

            $merge = Arr::only($data, [
                'oom_disabled',
                'memory',
                'swap',
                'io',
                'cpu',
                'threads',
                'disk',
                'allocation_id',
            ]);

            $server->forceFill(array_merge($merge, [
                'database_limit' => Arr::get($data, 'database_limit', 0) ?? null,
                'allocation_limit' => Arr::get($data, 'allocation_limit', 0) ?? null,
                'backup_limit' => Arr::get($data, 'backup_limit', 0) ?? 0,
            ]))->saveOrFail();

            return $server->refresh();
        });

        $updateData = $this->structureService->handle($server);

        if (!empty($updateData['build'])) {
            try {
                $this->daemonServerRepository->setServer($server)->sync();
            } catch (DaemonConnectionException $exception) {
                Log::warning($exception, ['server_id' => $server->id]);
            }
        }

        return $server;
    }

    private function processAllocations(Server $server, array &$data): void
    {
        if (empty($data['add_allocations']) && empty($data['remove_allocations'])) {
            return;
        }

        if (!empty($data['add_allocations'])) {
            $query = Allocation::query()
                ->where('node_id', $server->node_id)
                ->whereIn('id', $data['add_allocations'])
                ->whereNull('server_id');

            $freshlyAllocated = $query->pluck('id')->first();

            $query->update(['server_id' => $server->id, 'notes' => null]);
        }

        if (!empty($data['remove_allocations'])) {
            foreach ($data['remove_allocations'] as $allocation) {
                if ($allocation === ($data['allocation_id'] ?? $server->allocation_id)) {
                    if (empty($freshlyAllocated)) {
                        throw new DisplayException(
                            'You are attempting to delete the default allocation for this server but there is no fallback allocation to use.'
                        );
                    }
                    $data['allocation_id'] = $freshlyAllocated;
                }
            }

            Allocation::query()
                ->where('node_id', $server->node_id)
                ->where('server_id', $server->id)
                ->whereIn('id', array_diff($data['remove_allocations'], $data['add_allocations'] ?? []))
                ->update([
                    'notes' => null,
                    'server_id' => null,
                ]);
        }
    }
}
PHPEOF

install_file \
  "PROTECT1 — Anti Update Build Configuration Server" \
  "/var/www/pterodactyl/app/Services/Servers/BuildModificationService.php" \
  "$TMP4"
rm -f "$TMP4"

# ========================================================
# 5. StartupModificationService.php
# ========================================================
echo -e "${YELLOW}▶️  [5] StartupModificationService.php${NC}"

TMP5="$(mktemp)"
cat > "$TMP5" <<'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Arr;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\ServerVariable;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Traits\Services\HasUserLevels;
use Pterodactyl\Exceptions\DisplayException;

class StartupModificationService
{
    use HasUserLevels;

    public function __construct(
        private ConnectionInterface $connection,
        private VariableValidatorService $validatorService
    ) {
    }

    public function handle(Server $server, array $data): Server
    {
        $user = auth()->user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id ?? null;

            if ($ownerId !== $user->id) {
                throw new DisplayException(
                    '🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mengubah startup command server orang lain'
                );
            }
        }

        return $this->connection->transaction(function () use ($server, $data) {
            if (!empty($data['environment'])) {
                $egg = $this->isUserLevel(User::USER_LEVEL_ADMIN)
                    ? ($data['egg_id'] ?? $server->egg_id)
                    : $server->egg_id;

                $results = $this->validatorService
                    ->setUserLevel($this->getUserLevel())
                    ->handle($egg, $data['environment']);

                foreach ($results as $result) {
                    ServerVariable::query()->updateOrCreate(
                        [
                            'server_id' => $server->id,
                            'variable_id' => $result->id,
                        ],
                        ['variable_value' => $result->value ?? '']
                    );
                }
            }

            if ($this->isUserLevel(User::USER_LEVEL_ADMIN)) {
                $this->updateAdministrativeSettings($data, $server);
            }

            return $server->fresh();
        });
    }

    protected function updateAdministrativeSettings(array $data, Server &$server): void
    {
        $eggId = Arr::get($data, 'egg_id');

        if (is_digit($eggId) && $server->egg_id !== (int) $eggId) {
            $egg = Egg::query()->findOrFail($data['egg_id']);

            $server = $server->forceFill([
                'egg_id' => $egg->id,
                'nest_id' => $egg->nest_id,
            ]);
        }

        $server->fill([
            'startup' => $data['startup'] ?? $server->startup,
            'skip_scripts' => $data['skip_scripts'] ?? isset($data['skip_scripts']),
            'image' => $data['docker_image'] ?? $server->image,
        ])->save();
    }
}
PHPEOF

install_file \
  "PROTECT1 — Anti Setup Server" \
  "/var/www/pterodactyl/app/Services/Servers/StartupModificationService.php" \
  "$TMP5"
rm -f "$TMP5"

# ========================================================
# 6. DatabaseManagementService.php
# ========================================================
echo -e "${YELLOW}▶️  [6] DatabaseManagementService.php${NC}"

TMP6="$(mktemp)"
cat > "$TMP6" <<'PHPEOF'
<?php

namespace Pterodactyl\Services\Databases;

use Exception;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Database;
use Pterodactyl\Helpers\Utilities;
use Illuminate\Database\ConnectionInterface;
use Illuminate\Contracts\Encryption\Encrypter;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Extensions\DynamicDatabaseConnection;
use Pterodactyl\Repositories\Eloquent\DatabaseRepository;
use Pterodactyl\Exceptions\Repository\DuplicateDatabaseNameException;
use Pterodactyl\Exceptions\Service\Database\TooManyDatabasesException;
use Pterodactyl\Exceptions\Service\Database\DatabaseClientFeatureNotEnabledException;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Support\Facades\Log;

class DatabaseManagementService
{
    private const MATCH_NAME_REGEX = '/^(s[\d]+_)(.*)$/';

    protected bool $validateDatabaseLimit = true;

    public function __construct(
        protected ConnectionInterface $connection,
        protected DynamicDatabaseConnection $dynamic,
        protected Encrypter $encrypter,
        protected DatabaseRepository $repository
    ) {
    }

    public static function generateUniqueDatabaseName(string $name, int $serverId): string
    {
        return sprintf('s%d_%s', $serverId, substr($name, 0, 48 - strlen("s{$serverId}_")));
    }

    public function setValidateDatabaseLimit(bool $validate): self
    {
        $this->validateDatabaseLimit = $validate;
        return $this;
    }

    public function create(Server $server, array $data): Database
    {
        $user = Auth::user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id ?? $server->user_id ?? null;

            if ($ownerId !== $user->id) {
                throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat membuat database untuk server orang lain');
            }
        }

        if (!config('pterodactyl.client_features.databases.enabled')) {
            throw new DatabaseClientFeatureNotEnabledException();
        }

        if ($this->validateDatabaseLimit) {
            if (!is_null($server->database_limit) && $server->databases()->count() >= $server->database_limit) {
                throw new TooManyDatabasesException();
            }
        }

        if (empty($data['database']) || !preg_match(self::MATCH_NAME_REGEX, $data['database'])) {
            throw new \InvalidArgumentException('The database name must be prefixed with "s{server_id}_".');
        }

        $data = array_merge($data, [
            'server_id' => $server->id,
            'username' => sprintf('u%d_%s', $server->id, str_random(10)),
            'password' => $this->encrypter->encrypt(
                Utilities::randomStringWithSpecialCharacters(24)
            ),
        ]);

        $database = null;

        try {
            return $this->connection->transaction(function () use ($data, &$database) {
                $database = $this->createModel($data);

                $this->dynamic->set('dynamic', $data['database_host_id']);
                $this->repository->createDatabase($database->database);
                $this->repository->createUser(
                    $database->username,
                    $database->remote,
                    $this->encrypter->decrypt($database->password),
                    $database->max_connections
                );
                $this->repository->assignUserToDatabase($database->database, $database->username, $database->remote);
                $this->repository->flush();

                return $database;
            });
        } catch (\Exception $exception) {
            try {
                if ($database instanceof Database) {
                    $this->repository->dropDatabase($database->database);
                    $this->repository->dropUser($database->username, $database->remote);
                    $this->repository->flush();
                }
            } catch (\Exception $deletionException) {
            }

            throw $exception;
        }
    }

    public function delete(Database $database): ?bool
    {
        $user = Auth::user();

        if ($user && $user->id !== 1) {
            $server = Server::find($database->server_id);
            if ($server && $server->owner_id !== $user->id) {
                throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat menghapus database server orang lain');
            }
        }

        $this->dynamic->set('dynamic', $database->database_host_id);

        $this->repository->dropDatabase($database->database);
        $this->repository->dropUser($database->username, $database->remote);
        $this->repository->flush();

        return $database->delete();
    }

    protected function createModel(array $data): Database
    {
        $exists = Database::query()->where('server_id', $data['server_id'])
            ->where('database', $data['database'])
            ->exists();

        if ($exists) {
            throw new DuplicateDatabaseNameException('A database with that name already exists for this server.');
        }

        $database = (new Database())->forceFill($data);
        $database->saveOrFail();

        return $database;
    }
}
PHPEOF

install_file \
  "PROTECT1 — Anti Update Database" \
  "/var/www/pterodactyl/app/Services/Databases/DatabaseManagementService.php" \
  "$TMP6"
rm -f "$TMP6"

# ========================================================
# 7. ServerTransferController.php
# ========================================================
echo -e "${YELLOW}▶️  [7] ServerTransferController.php${NC}"

TMP7="$(mktemp)"
cat > "$TMP7" <<'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Servers;

use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Pterodactyl\Models\Server;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Models\ServerTransfer;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Nodes\NodeJWTService;
use Pterodactyl\Repositories\Eloquent\NodeRepository;
use Pterodactyl\Repositories\Wings\DaemonTransferRepository;
use Pterodactyl\Contracts\Repository\AllocationRepositoryInterface;
use Pterodactyl\Exceptions\DisplayException;

class ServerTransferController extends Controller
{
    public function __construct(
        private AlertsMessageBag $alert,
        private AllocationRepositoryInterface $allocationRepository,
        private ConnectionInterface $connection,
        private DaemonTransferRepository $daemonTransferRepository,
        private NodeJWTService $nodeJWTService,
        private NodeRepository $nodeRepository
    ) {
    }

    public function transfer(Request $request, Server $server): RedirectResponse
    {
        $user = auth()->user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id
                ?? $server->user_id
                ?? ($server->owner?->id ?? null)
                ?? ($server->user?->id ?? null);

            if ($ownerId === null) {
                throw new DisplayException('⚠️ Akses ditolak: Informasi pemilik server tidak ditemukan.');
            }

            if ($ownerId !== $user->id) {
                throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mentransfer server orang lain');
            }
        }

        $validatedData = $request->validate([
            'node_id' => 'required|exists:nodes,id',
            'allocation_id' => 'required|bail|unique:servers|exists:allocations,id',
            'allocation_additional' => 'nullable',
        ]);

        $node_id = $validatedData['node_id'];
        $allocation_id = intval($validatedData['allocation_id']);
        $additional_allocations = array_map('intval', $validatedData['allocation_additional'] ?? []);

        $node = $this->nodeRepository->getNodeWithResourceUsage($node_id);
        if (!$node->isViable($server->memory, $server->disk)) {
            $this->alert->danger(trans('admin/server.alerts.transfer_not_viable'))->flash();

            return redirect()->route('admin.servers.view.manage', $server->id);
        }

        $server->validateTransferState();

        $this->connection->transaction(function () use ($server, $node_id, $allocation_id, $additional_allocations) {
            $transfer = new ServerTransfer();

            $transfer->server_id = $server->id;
            $transfer->old_node = $server->node_id;
            $transfer->new_node = $node_id;
            $transfer->old_allocation = $server->allocation_id;
            $transfer->new_allocation = $allocation_id;
            $transfer->old_additional_allocations = $server->allocations->where('id', '!=', $server->allocation_id)->pluck('id');
            $transfer->new_additional_allocations = $additional_allocations;

            $transfer->save();

            $this->assignAllocationsToServer($server, $node_id, $allocation_id, $additional_allocations);

            $token = $this->nodeJWTService
                ->setExpiresAt(CarbonImmutable::now()->addMinutes(15))
                ->setSubject($server->uuid)
                ->handle($transfer->newNode, $server->uuid, 'sha256');

            $this->daemonTransferRepository->setServer($server)->notify($transfer->newNode, $token);

            return $transfer;
        });

        $this->alert->success(trans('admin/server.alerts.transfer_started'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    private function assignAllocationsToServer(Server $server, int $node_id, int $allocation_id, array $additional_allocations)
    {
        $allocations = $additional_allocations;
        $allocations[] = $allocation_id;

        $unassigned = $this->allocationRepository->getUnassignedAllocationIds($node_id);

        $updateIds = [];
        foreach ($allocations as $allocation) {
            if (!in_array($allocation, $unassigned)) {
                continue;
            }

            $updateIds[] = $allocation;
        }

        if (!empty($updateIds)) {
            $this->allocationRepository->updateWhereIn('id', $updateIds, ['server_id' => $server->id]);
        }
    }
}
PHPEOF

install_file \
  "PROTECT1 — Anti Button Transfer This Server" \
  "/var/www/pterodactyl/app/Http/Controllers/Admin/Servers/ServerTransferController.php" \
  "$TMP7"
rm -f "$TMP7"

# ========================================================
# 8. ServersController.php
# ========================================================
echo -e "${YELLOW}▶️  [8] ServersController.php${NC}"

TMP8="$(mktemp)"
cat > "$TMP8" <<'PHPEOF'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Illuminate\Http\Response;
use Pterodactyl\Models\Mount;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Database;
use Pterodactyl\Models\MountServer;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Validation\ValidationException;
use Pterodactyl\Services\Servers\SuspensionService;
use Pterodactyl\Repositories\Eloquent\MountRepository;
use Pterodactyl\Services\Servers\ServerDeletionService;
use Pterodactyl\Services\Servers\ReinstallServerService;
use Pterodactyl\Exceptions\Model\DataValidationException;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Servers\BuildModificationService;
use Pterodactyl\Services\Databases\DatabasePasswordService;
use Pterodactyl\Services\Servers\DetailsModificationService;
use Pterodactyl\Services\Servers\StartupModificationService;
use Pterodactyl\Contracts\Repository\NestRepositoryInterface;
use Pterodactyl\Repositories\Eloquent\DatabaseHostRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Illuminate\Contracts\Config\Repository as ConfigRepository;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Pterodactyl\Contracts\Repository\DatabaseRepositoryInterface;
use Pterodactyl\Contracts\Repository\AllocationRepositoryInterface;
use Pterodactyl\Services\Servers\ServerConfigurationStructureService;
use Pterodactyl\Http\Requests\Admin\Servers\Databases\StoreServerDatabaseRequest;

class ServersController extends Controller
{
    public function __construct(
        protected AlertsMessageBag $alert,
        protected AllocationRepositoryInterface $allocationRepository,
        protected BuildModificationService $buildModificationService,
        protected ConfigRepository $config,
        protected DaemonServerRepository $daemonServerRepository,
        protected DatabaseManagementService $databaseManagementService,
        protected DatabasePasswordService $databasePasswordService,
        protected DatabaseRepositoryInterface $databaseRepository,
        protected DatabaseHostRepository $databaseHostRepository,
        protected ServerDeletionService $deletionService,
        protected DetailsModificationService $detailsModificationService,
        protected ReinstallServerService $reinstallService,
        protected ServerRepositoryInterface $repository,
        protected MountRepository $mountRepository,
        protected NestRepositoryInterface $nestRepository,
        protected ServerConfigurationStructureService $serverConfigurationStructureService,
        protected StartupModificationService $startupModificationService,
        protected SuspensionService $suspensionService
    ) {
    }

    public function setDetails(Request $request, Server $server): RedirectResponse
    {
        $this->detailsModificationService->handle($server, $request->only([
            'owner_id', 'external_id', 'name', 'description',
        ]));

        $this->alert->success(trans('admin/server.alerts.details_updated'))->flash();

        return redirect()->route('admin.servers.view.details', $server->id);
    }

    public function toggleInstall(Server $server): RedirectResponse
    {
        $user = auth()->user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id
                ?? $server->user_id
                ?? ($server->owner?->id ?? null)
                ?? ($server->user?->id ?? null);

            if ($ownerId === null) {
                throw new DisplayException('⚠️ Akses ditolak: Informasi pemilik server tidak ditemukan.');
            }

            if ($ownerId !== $user->id) {
                throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mengubah status instalasi server orang lain');
            }
        }

        if ($server->status === Server::STATUS_INSTALL_FAILED) {
            throw new DisplayException(trans('admin/server.exceptions.marked_as_failed'));
        }

        $this->repository->update($server->id, [
            'status' => $server->isInstalled() ? Server::STATUS_INSTALLING : null,
        ], true, true);

        $this->alert->success(trans('admin/server.alerts.install_toggled'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    public function reinstallServer(Server $server): RedirectResponse
    {
        $this->reinstallService->handle($server);
        $this->alert->success(trans('admin/server.alerts.server_reinstalled'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    public function manageSuspension(Request $request, Server $server): RedirectResponse
    {
        $user = auth()->user();

        if ($user && $user->id !== 1) {
            $ownerId = $server->owner_id
                ?? $server->user_id
                ?? ($server->owner?->id ?? null)
                ?? ($server->user?->id ?? null);

            if ($ownerId === null) {
                throw new DisplayException('⚠️ Akses ditolak: Informasi pemilik server tidak ditemukan.');
            }

            if ($ownerId !== $user->id) {
                throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat mensuspend server orang lain');
            }
        }

        $this->suspensionService->toggle($server, $request->input('action'));

        $this->alert->success(trans('admin/server.alerts.suspension_toggled', [
            'status' => $request->input('action') . 'ed',
        ]))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    public function updateBuild(Request $request, Server $server): RedirectResponse
    {
        try {
            $this->buildModificationService->handle($server, $request->only([
                'allocation_id', 'add_allocations', 'remove_allocations',
                'memory', 'swap', 'io', 'cpu', 'threads', 'disk',
                'database_limit', 'allocation_limit', 'backup_limit', 'oom_disabled',
            ]));
        } catch (DataValidationException $exception) {
            throw new ValidationException($exception->getValidator());
        }

        $this->alert->success(trans('admin/server.alerts.build_updated'))->flash();

        return redirect()->route('admin.servers.view.build', $server->id);
    }

    public function delete(Request $request, Server $server): RedirectResponse
    {
        $this->deletionService->withForce($request->filled('force_delete'))->handle($server);
        $this->alert->success(trans('admin/server.alerts.server_deleted'))->flash();

        return redirect()->route('admin.servers');
    }

    public function saveStartup(Request $request, Server $server): RedirectResponse
    {
        $data = $request->except('_token');
        if (!empty($data['custom_docker_image'])) {
            $data['docker_image'] = $data['custom_docker_image'];
            unset($data['custom_docker_image']);
        }

        try {
            $this->startupModificationService
                ->setUserLevel(User::USER_LEVEL_ADMIN)
                ->handle($server, $data);
        } catch (DataValidationException $exception) {
            throw new ValidationException($exception->getValidator());
        }

        $this->alert->success(trans('admin/server.alerts.startup_changed'))->flash();

        return redirect()->route('admin.servers.view.startup', $server->id);
    }

    public function newDatabase(StoreServerDatabaseRequest $request, Server $server): RedirectResponse
    {
        $this->databaseManagementService->create($server, [
            'database' => DatabaseManagementService::generateUniqueDatabaseName($request->input('database'), $server->id),
            'remote' => $request->input('remote'),
            'database_host_id' => $request->input('database_host_id'),
            'max_connections' => $request->input('max_connections'),
        ]);

        return redirect()->route('admin.servers.view.database', $server->id)->withInput();
    }

    public function resetDatabasePassword(Request $request, Server $server): Response
    {
        $database = $server->databases()->findOrFail($request->input('database'));

        $this->databasePasswordService->handle($database);

        return response('', 204);
    }

    public function deleteDatabase(Server $server, Database $database): Response
    {
        $this->databaseManagementService->delete($database);

        return response('', 204);
    }

    public function addMount(Request $request, Server $server): RedirectResponse
    {
        $mountServer = (new MountServer())->forceFill([
            'mount_id' => $request->input('mount_id'),
            'server_id' => $server->id,
        ]);

        $mountServer->saveOrFail();

        $this->alert->success('Mount was added successfully.')->flash();

        return redirect()->route('admin.servers.view.mounts', $server->id);
    }

    public function deleteMount(Server $server, Mount $mount): RedirectResponse
    {
        MountServer::where('mount_id', $mount->id)->where('server_id', $server->id)->delete();

        $this->alert->success('Mount was removed successfully.')->flash();

        return redirect()->route('admin.servers.view.mounts', $server->id);
    }
}
PHPEOF

install_file \
  "PROTECT1 — Anti Update Manage (Suspend, Install, Toggle Status)" \
  "/var/www/pterodactyl/app/Http/Controllers/Admin/ServersController.php" \
  "$TMP8"
rm -f "$TMP8"

# ========================================================
# 9. ReinstallServerService.php
# ========================================================
echo -e "${YELLOW}▶️  [9] ReinstallServerService.php${NC}"

TMP9="$(mktemp)"
cat > "$TMP9" <<'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Models\Server;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Illuminate\Support\Facades\Log;

class ReinstallServerService
{
    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository
    ) {}

    public function handle(Server $server): Server
    {
        $user = Auth::user();

        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id
                    ?? $server->user_id
                    ?? ($server->owner?->id ?? null)
                    ?? ($server->user?->id ?? null);

                if ($ownerId === null) {
                    throw new DisplayException('Akses ditolak: informasi pemilik server tidak tersedia.');
                }

                if ($ownerId !== $user->id) {
                    throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat me-reinstall server orang lain');
                }
            }
        }

        Log::channel('daily')->info('🔄 Reinstall Server', [
            'server_id' => $server->id,
            'server_name' => $server->name ?? 'Unknown',
            'reinstalled_by' => $user?->id ?? 'CLI/Unknown',
            'time' => now()->toDateTimeString(),
        ]);

        return $this->connection->transaction(function () use ($server) {
            $server->fill(['status' => Server::STATUS_INSTALLING])->save();

            $this->daemonServerRepository->setServer($server)->reinstall();

            return $server->refresh();
        });
    }
}
PHPEOF

install_file \
  "PROTECT1 — Anti Button Reinstall Status" \
  "/var/www/pterodactyl/app/Services/Servers/ReinstallServerService.php" \
  "$TMP9"
rm -f "$TMP9"

# ========================================================
# 10. ServerDeletionService.php
# ========================================================
echo -e "${YELLOW}▶️  [10] ServerDeletionService.php${NC}"

TMP10="$(mktemp)"
cat > "$TMP10" <<'PHPEOF'
<?php

namespace Pterodactyl\Services\Servers;

use Illuminate\Support\Facades\Auth;
use Pterodactyl\Exceptions\DisplayException;
use Illuminate\Http\Response;
use Pterodactyl\Models\Server;
use Illuminate\Support\Facades\Log;
use Illuminate\Database\ConnectionInterface;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Pterodactyl\Exceptions\Http\Connection\DaemonConnectionException;

class ServerDeletionService
{
    protected bool $force = false;

    public function __construct(
        private ConnectionInterface $connection,
        private DaemonServerRepository $daemonServerRepository,
        private DatabaseManagementService $databaseManagementService
    ) {}

    public function withForce(bool $bool = true): self
    {
        $this->force = $bool;
        return $this;
    }

    public function handle(Server $server): void
    {
        $user = Auth::user();

        if ($user) {
            if ($user->id !== 1) {
                $ownerId = $server->owner_id
                    ?? $server->user_id
                    ?? ($server->owner?->id ?? null)
                    ?? ($server->user?->id ?? null);

                if ($ownerId === null) {
                    throw new DisplayException('Akses ditolak: informasi pemilik server tidak tersedia.');
                }

                if ($ownerId !== $user->id) {
                    throw new DisplayException('🚫 Akses ditolak: Hanya Admin ID 1 yang dapat menghapus server orang lain');
                }
            }
        }

        if ($this->force === true) {
            Log::channel('daily')->info('⚠️ FORCE DELETE DETECTED', [
                'server_id' => $server->id,
                'server_name' => $server->name ?? 'Unknown',
                'deleted_by' => $user?->id ?? 'CLI/Unknown',
                'time' => now()->toDateTimeString(),
            ]);

            Log::build([
                'driver' => 'single',
                'path' => storage_path('logs/force_delete.log'),
            ])->info("⚠️ FORCE DELETE SERVER #{$server->id} ({$server->name}) oleh User ID {$user?->id}");
        }

        try {
            $this->daemonServerRepository->setServer($server)->delete();
        } catch (DaemonConnectionException $exception) {
            if (!$this->force && $exception->getStatusCode() !== Response::HTTP_NOT_FOUND) {
                throw $exception;
            }
            Log::warning($exception);
        }

        $this->connection->transaction(function () use ($server) {
            foreach ($server->databases as $database) {
                try {
                    $this->databaseManagementService->delete($database);
                } catch (\Exception $exception) {
                    if (!$this->force) throw $exception;
                    $database->delete();
                    Log::warning($exception);
                }
            }

            $server->delete();
        });
    }
}
PHPEOF

install_file \
  "PROTECT1 — Anti Delete Server" \
  "/var/www/pterodactyl/app/Services/Servers/ServerDeletionService.php" \
  "$TMP10"
rm -f "$TMP10"

# ========================================================
# CLEAR CACHE & FIX PERMISSION
# ========================================================
echo ""
echo -e "${YELLOW}🧹 Clear cache & fix permission...${NC}"

cd "$PANEL_DIR" || exit 1

php artisan optimize:clear --no-interaction 2>/dev/null || true

chown -R www-data:www-data "$PANEL_DIR/app" "$PANEL_DIR/resources" 2>/dev/null || true
find "$PANEL_DIR/app" "$PANEL_DIR/resources" -type f -exec chmod 644 {} + 2>/dev/null || true
find "$PANEL_DIR/app" "$PANEL_DIR/resources" -type d -exec chmod 755 {} + 2>/dev/null || true

systemctl restart php*-fpm 2>/dev/null || true
systemctl reload nginx 2>/dev/null || true

# ========================================================
# RINGKASAN
# ========================================================
echo ""
echo -e "${CYAN}${BOLD}========================================${NC}"
echo -e "${MAGENTA}${BOLD}   📊 HASIL INSTALL PROTECT${NC}"
echo -e "${CYAN}${BOLD}========================================${NC}"
echo -e "${GREEN}┌ ✅ Sukses   : ${SUKSES}${NC}"
echo -e "${RED}├ ❌ Gagal    : ${GAGAL}${NC}"
echo -e "${CYAN}├ 💾 Backup   : ${BACKUP_DIR}${NC}"
echo -e "${CYAN}└ 🏁 Status   : $([ "$GAGAL" -eq 0 ] && echo -e "${GREEN}${BOLD}SELESAI${NC}" || echo -e "${RED}${BOLD}ADA GAGAL${NC}")${NC}"
echo -e "${CYAN}${BOLD}========================================${NC}"

if [ "$GAGAL" -gt 0 ]; then
  exit 1
fi

exit 0
