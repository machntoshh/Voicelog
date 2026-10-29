import 'dart:async';

import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../format.dart';
import '../models.dart';
import '../services/recorder_controller.dart';
import 'app_scope.dart';
import 'dialogs.dart';
import 'recorder_bar.dart';
import 'recording_tile.dart';
import 'theme.dart';
import 'transcription_settings.dart';

/// What the list shows: every recording, the unfiled ones, or one folder.
sealed class HomeView {
  const HomeView();
}

class RecentView extends HomeView {
  const RecentView();
}

class UnfiledView extends HomeView {
  const UnfiledView();
}

class FolderView extends HomeView {
  const FolderView(this.folderId);
  final String folderId;
}

const _wideBreakpoint = 760.0;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeView _view = const RecentView();
  SortMode _sort = SortMode.newest;
  final _search = TextEditingController();
  StreamSubscription<RecordingResult>? _results;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_results != null) return;
    final scope = AppScope.of(context);
    _results = scope.recorder.results.listen(_onRecordingFinished);
    final recovered = scope.store.recoveredOnLoad;
    if (recovered > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showMessage(
          context,
          recovered == 1
              ? '1 gravação interrompida foi recuperada em Sem pasta.'
              : '$recovered gravações interrompidas foram recuperadas em Sem pasta.'));
    }
  }

  @override
  void dispose() {
    _results?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _onRecordingFinished(RecordingResult result) async {
    if (!mounted) return;
    if (result.message != null) showMessage(context, result.message!, error: result.recording == null);
    final r = result.recording;
    if (r == null) return;
    final store = AppScope.of(context).store;
    // Pre-select the folder being viewed; the user can change it.
    if (_view case FolderView(:final folderId)) await store.moveRecording(r, folderId);
    if (!mounted) return;
    final transcriber = AppScope.of(context).transcriber;
    final saved = await showSaveDialog(context, store, r);
    transcriber.onRecordingSaved(r);
    if (!saved && mounted) showMessage(context, 'Gravação guardada como "${r.name}".');
  }

  Future<void> _createFolder() async {
    final store = AppScope.of(context).store;
    final name = await promptText(context,
        title: 'Nova pasta', hint: 'Ex.: Diário — ${formatDate(DateTime.now())}', confirm: 'Criar');
    if (name == null) return;
    final f = await store.createFolder(name);
    setState(() => _view = FolderView(f.id));
  }

  Future<void> _renameFolder(Folder f) async {
    final store = AppScope.of(context).store;
    final name = await promptText(context, title: 'Renomear pasta', initial: f.name);
    if (name != null) await store.renameFolder(f, name);
  }

  Future<void> _deleteFolder(Folder f) async {
    final store = AppScope.of(context).store;
    final choice = await askDeleteFolder(context, f, store.countIn(f.id));
    if (choice == null) return;
    await store.deleteFolder(f, deleteRecordings: choice == DeleteFolderChoice.deleteRecordings);
    if (!mounted) return;
    setState(() => _view = const RecentView());
    showMessage(context, 'Pasta excluída');
  }

  Future<void> _drop(Recording r, String? folderId) async {
    final store = AppScope.of(context).store;
    if (r.folderId == folderId) return;
    await store.moveRecording(r, folderId);
    if (mounted) showMessage(context, 'Movida para ${store.folderById(folderId)?.name ?? 'Sem pasta'}');
  }

  void _select(HomeView v) {
    setState(() {
      _view = v;
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            // A folder deleted elsewhere falls back to the recent list.
            if (_view case FolderView(:final folderId) when store.folderById(folderId) == null) {
              _view = const RecentView();
            }
            return LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= _wideBreakpoint;
              final content = _content(store, wide);
              if (!wide) return content;
              return Row(children: [
                SizedBox(width: 270, child: _Sidebar(state: this, store: store)),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ]);
            });
          },
        ),
      ),
      bottomNavigationBar: const RecorderBar(),
    );
  }

  Widget _content(LibraryStore store, bool wide) {
    final query = _search.text.trim();
    final searching = query.isNotEmpty;
    final List<Recording> items;
    Map<Recording, SearchHit> hits = const {};
    final String title;
    Folder? folder;
    switch (_view) {
      case _ when searching:
        hits = {for (final h in store.search(query)) h.recording: h};
        items = hits.keys.toList();
        title = 'Resultados';
      case RecentView():
        items = store.allReady;
        title = 'Recentes';
      case UnfiledView():
        items = store.inFolder(null);
        title = 'Sem pasta';
      case FolderView(:final folderId):
        folder = store.folderById(folderId);
        items = store.inFolder(folderId);
        title = folder?.name ?? '';
    }
    LibraryStore.sorted(items, _sort);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Row(children: [
          if (!wide) ...[const _Logo(), const SizedBox(width: 12)],
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: wide ? 'Pesquisar por nome, data, pasta ou fala' : 'Pesquisar',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searching
                    ? IconButton(
                        tooltip: 'Limpar',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(_search.clear),
                      )
                    : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Transcrição',
            onPressed: () => showTranscriptionSettings(context),
            icon: const Icon(Icons.closed_caption_outlined),
          ),
          PopupMenuButton<SortMode>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (m) => setState(() => _sort = m),
            itemBuilder: (_) => const [
              PopupMenuItem(value: SortMode.newest, child: Text('Mais recentes')),
              PopupMenuItem(value: SortMode.oldest, child: Text('Mais antigas')),
              PopupMenuItem(value: SortMode.name, child: Text('Nome (A–Z)')),
            ],
          ),
        ]),
      ),
      if (!wide) _FolderStrip(state: this, store: store),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
        child: Row(children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Text('${items.length}', style: const TextStyle(color: VL.textFaint, fontFeatures: VL.tabular)),
          if (folder != null && !searching)
            PopupMenuButton<String>(
              tooltip: 'Ações da pasta',
              icon: const Icon(Icons.more_horiz, color: VL.textDim),
              onSelected: (v) => v == 'rename' ? _renameFolder(folder!) : _deleteFolder(folder!),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Renomear pasta')),
                PopupMenuItem(value: 'delete', child: Text('Excluir pasta', style: TextStyle(color: VL.red))),
              ],
            )
          else
            const SizedBox(width: 12),
        ]),
      ),
      Expanded(
        child: items.isEmpty
            ? _Empty(searching: searching)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => RecordingTile(
                  key: ValueKey(items[i].id),
                  recording: items[i],
                  showFolder: searching || _view is RecentView,
                  hit: hits[items[i]],
                ),
              ),
      ),
    ]);
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: const BoxDecoration(color: VL.red, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        const Text('VOICELOG', style: TextStyle(letterSpacing: 2.2, fontWeight: FontWeight.w700, fontSize: 14)),
      ]);
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(searching ? Icons.search_off : Icons.mic_none_rounded, size: 40, color: VL.textFaint),
            const SizedBox(height: 12),
            Text(
              searching ? 'Nenhuma gravação encontrada.' : 'Nenhuma gravação aqui.\nToque no botão vermelho para gravar.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: VL.textDim),
            ),
          ]),
        ),
      );
}

String _folderSubtitle(LibraryStore store, String? folderId) {
  final n = store.countIn(folderId);
  final last = store.lastRecordingIn(folderId);
  final count = n == 1 ? '1 gravação' : '$n gravações';
  return last == null ? count : '$count · ${formatDate(last)}';
}

/// Highlights while a recording is dragged over it and moves it on drop.
class _DropTarget extends StatelessWidget {
  const _DropTarget({required this.state, required this.folderId, required this.builder});

  final _HomePageState state;
  final String? folderId;
  final Widget Function(bool hovering) builder;

  @override
  Widget build(BuildContext context) => DragTarget<Recording>(
        onWillAcceptWithDetails: (d) => d.data.folderId != folderId,
        onAcceptWithDetails: (d) => state._drop(d.data, folderId),
        builder: (context, candidates, _) => builder(candidates.isNotEmpty),
      );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state, required this.store});

  final _HomePageState state;
  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    final view = state._view;
    Widget entry({
      required IconData icon,
      required String label,
      String? subtitle,
      required bool selected,
      required HomeView target,
      bool droppable = true,
      String? folderId,
    }) {
      Widget tile(bool hovering) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Material(
              color: hovering ? VL.redSoft : (selected ? VL.panelHigh : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => state._select(target),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(children: [
                    Icon(icon, size: 19, color: selected ? VL.text : VL.textDim),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (subtitle != null)
                          Text(subtitle,
                              style: const TextStyle(fontSize: 11.5, color: VL.textFaint, fontFeatures: VL.tabular)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          );
      return droppable ? _DropTarget(state: state, folderId: folderId, builder: tile) : tile(false);
    }

    return Container(
      color: VL.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.fromLTRB(22, 22, 16, 18), child: _Logo()),
        entry(
          icon: Icons.schedule_rounded,
          label: 'Recentes',
          selected: view is RecentView,
          target: const RecentView(),
          droppable: false,
        ),
        entry(
          icon: Icons.inbox_outlined,
          label: 'Sem pasta',
          subtitle: _folderSubtitle(store, null),
          selected: view is UnfiledView,
          target: const UnfiledView(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 10, 6),
          child: Row(children: [
            const Expanded(
              child: Text('PASTAS', style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: VL.textFaint)),
            ),
            IconButton(
              tooltip: 'Nova pasta',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              onPressed: state._createFolder,
              icon: const Icon(Icons.create_new_folder_outlined, color: VL.textDim),
            ),
          ]),
        ),
        Expanded(
          child: ListView(children: [
            for (final f in store.sortedFolders(state._sort))
              entry(
                icon: Icons.folder_outlined,
                label: f.name,
                subtitle: _folderSubtitle(store, f.id),
                selected: view is FolderView && view.folderId == f.id,
                target: FolderView(f.id),
                folderId: f.id,
              ),
            if (store.folders.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 4, 16, 0),
                child: Text('Crie pastas para organizar por dia ou assunto.',
                    style: TextStyle(color: VL.textFaint, fontSize: 12.5)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Compact, horizontally scrolling folder row for phones. Folders accept
/// long-press-dragged recordings.
class _FolderStrip extends StatelessWidget {
  const _FolderStrip({required this.state, required this.store});

  final _HomePageState state;
  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    final view = state._view;
    Widget chip({
      required IconData icon,
      required String label,
      String? subtitle,
      required bool selected,
      required HomeView target,
      bool droppable = true,
      String? folderId,
    }) {
      Widget body(bool hovering) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: hovering ? VL.redSoft : (selected ? VL.panelHigh : VL.panel),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: selected ? VL.textFaint : VL.border, width: 0.6),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => state._select(target),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 96, maxWidth: 170),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, size: 16, color: selected ? VL.text : VL.textDim),
                      const SizedBox(width: 6),
                      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                    if (subtitle != null)
                      Text(subtitle,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 11, color: VL.textFaint, fontFeatures: VL.tabular)),
                  ]),
                ),
              ),
            ),
          );
      return droppable ? _DropTarget(state: state, folderId: folderId, builder: body) : body(false);
    }

    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip(
            icon: Icons.schedule_rounded,
            label: 'Recentes',
            selected: view is RecentView,
            target: const RecentView(),
            droppable: false,
          ),
          chip(
            icon: Icons.inbox_outlined,
            label: 'Sem pasta',
            subtitle: _folderSubtitle(store, null),
            selected: view is UnfiledView,
            target: const UnfiledView(),
          ),
          for (final f in store.sortedFolders(state._sort))
            chip(
              icon: Icons.folder_outlined,
              label: f.name,
              subtitle: _folderSubtitle(store, f.id),
              selected: view is FolderView && view.folderId == f.id,
              target: FolderView(f.id),
              folderId: f.id,
            ),
          Center(
            child: IconButton.filledTonal(
              tooltip: 'Nova pasta',
              onPressed: state._createFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          ),
        ],
      ),
    );
  }
}
