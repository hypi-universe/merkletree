import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:hypi_merkletree/src/utils.dart';

typedef HashAlgo = Uint8List Function(Uint8List input);

/// Class representing a Merkle Tree
class MerkleTree {
  final HashAlgo hashAlgo;
  final List<List<Uint8List>> _layers;
  final bool isBitcoinTree;

  /// Constructs a Merkle Tree.
  /// All nodes and leaves are stored as [Uint8List].
  /// Lonely leaf nodes are promoted to the next level up without being hashed again.
  ///
  /// [leaves] is a list of hashed leaves. Each leaf must be a [Uint8List].
  /// [hashAlgo] is a [HashAlgo] function used for hashing leaves and nodes defined.
  /// [isBitcoinTree] decides whether to construct the MerkleTree using the [Bitcoin Merkle Tree implementation](http://www.righto.com/2014/02/bitcoin-mining-hard-way-algorithms.html).
  ///   Enable it when you need to replicate Bitcoin constructed Merkle Trees. In Bitcoin Merkle Trees, single nodes are combined with themselves, and each output hash is hashed again.
  ///
  /// ```dart
  /// import 'dart:typed_data';
  ///
  /// import 'package:convert/convert.dart';
  /// import 'package:merkletree/hypi_merkletree.dart';
  /// import 'package:pointycastle/pointycastle.dart';
  ///
  /// Uint8List sha3(Uint8List data) {
  ///   final sha3 = Digest("SHA-3/256");
  ///   return sha3.process(data);
  /// }
  ///
  /// List<Uint8List> leaves = ['a', 'b', 'c'].map((x) => Uint8List.fromList(x.codeUnits)).map((x) => sha3(x)).toList();
  /// final tree = MerkleTree(leaves: leaves, hashAlgo: sha256);
  /// ```
  MerkleTree({
    required List<Uint8List> leaves,
    required this.hashAlgo,
    this.isBitcoinTree = false,
  }) : _layers = [leaves] {
    _createHashes(leaves);
  }

  MerkleTree.fromTree({
    required List<List<Uint8List>> layers,
    required this.hashAlgo,
    this.isBitcoinTree = false,
  }) : _layers = layers;

  @override
  bool operator ==(Object other) =>
      //From List mixin - so we compare ourselves
      // Lists are, by default, only equal to themselves.
      // Even if [other] is also a list, the equality comparison
      // does not compare the elements of the two lists.
      identical(this, other) ||
      (other is MerkleTree &&
          0 == MerkleTreeUtils.bufferCompare(root, other.root));

  @override
  int get hashCode => Object.hashAll(root);

  void _createHashes(List<Uint8List> nodes) {
    while (nodes.length > 1) {
      final layerIndex = _layers.length;

      _layers.add([]);

      for (var i = 0; i < nodes.length - 1; i += 2) {
        final left = nodes[i];
        final right = nodes[i + 1];
        Uint8List data;

        if (isBitcoinTree) {
          data = MerkleTreeUtils.bufferConcat([
            MerkleTreeUtils.bufferReverse(left),
            MerkleTreeUtils.bufferReverse(right)
          ]);
        } else {
          data = MerkleTreeUtils.bufferConcat([left, right]);
        }

        var hash = hashAlgo(data);

        // double hash if bitcoin tree
        if (isBitcoinTree) {
          hash = MerkleTreeUtils.bufferReverse(hashAlgo(hash));
        }

        _layers[layerIndex].add(hash);
      }

      // is odd number of nodes
      if (nodes.length % 2 == 1) {
        var data = nodes[nodes.length - 1];
        var hash = data;

        // is bitcoin tree
        if (isBitcoinTree) {
          // Bitcoin method of duplicating the odd ending nodes
          data = MerkleTreeUtils.bufferConcat([
            MerkleTreeUtils.bufferReverse(data),
            MerkleTreeUtils.bufferReverse(data)
          ]);
          hash = hashAlgo(data);
          hash = MerkleTreeUtils.bufferReverse(hashAlgo(hash));
        }

        _layers[layerIndex].add(hash);
      }

      nodes = _layers[layerIndex];
    }
  }

  List<List<String>> get layersAsHex =>
      layers.map((e) => e.map((v) => hex.encode(v)).toList()).toList();

  /// Returns array of all layers of Merkle Tree, including leaves and root.
  List<List<Uint8List>> get layers {
    return _layers;
  }

  /// Returns the Merkle root hash as a Buffer.
  Uint8List get root {
    if (_layers.isEmpty) {
      return Uint8List(0);
    }

    if (_layers[_layers.length - 1].isEmpty) {
      return Uint8List(0);
    }

    return _layers[_layers.length - 1][0];
  }

  /// Returns the proof for a target leaf.
  /// [leaf] is the target leaf for this proof.
  /// [index] is the target leaf index in leaves array. Use only if there are leaves containing duplicate data in order to distinguish it.
  ///
  /// ```dart
  /// final proof = tree.getProof(leaf: leaves[2]);
  /// ```
  ///
  /// ```dart
  /// final leaves = ['a', 'b', 'a'].map((x) => Uint8List.fromList(x.codeUnits)).map((x) => sha3(x)).toList();
  /// final tree = MerkleTree(leaves: leaves, hashAlgo: sha3);
  /// final proof = tree.getProof(leaf: leaves[2], index: 2);
  /// ```
  List<MerkleProof> getProof({
    required Uint8List leaf,
    int index = -1,
  }) {
    final proof = <MerkleProof>[];
    List<Uint8List> leaves = layers[0];
    if (index == -1) {
      for (var i = 0; i < leaves.length; i++) {
        if (MerkleTreeUtils.bufferCompare(leaf, leaves[i]) == 0) {
          index = i;
        }
      }
    }

    if (index <= -1) {
      return [];
    }

    if (isBitcoinTree && index == (leaves.length - 1)) {
      // Proof Generation for Bitcoin Trees

      for (var i = 0; i < _layers.length - 1; i++) {
        final layer = _layers[i];
        final isRightNode = index % 2 == 1;
        final pairIndex = (isRightNode ? index - 1 : index);

        if (pairIndex < layer.length) {
          proof.add(MerkleProof(
              position: isRightNode
                  ? MerkleProofPosition.left
                  : MerkleProofPosition.right,
              data: layer[pairIndex]));
        }

        // set index to parent index
        index = (index / 2).floor();
      }

      return proof;
    } else {
      // Proof Generation for Non-Bitcoin Trees

      for (var i = 0; i < _layers.length; i++) {
        final layer = _layers[i];
        final isRightNode = index % 2 == 1;
        final pairIndex = (isRightNode ? index - 1 : index + 1);

        if (pairIndex < layer.length) {
          proof.add(MerkleProof(
              position: isRightNode
                  ? MerkleProofPosition.left
                  : MerkleProofPosition.right,
              data: layer[pairIndex]));
        }

        // set index to parent index
        index = (index / 2).floor();
      }

      return proof;
    }
  }

  /// Returns true if the proof path (array of hashes) can connect the target node to the Merkle root.
  /// [proof] is a list of [MerkleProof] objects that should connect target node to Merkle root.
  /// [targetNode] is the target node buffer.
  /// [root] is the Merkle root Buffer.
  ///
  /// ```dart
  /// final root = tree.getRoot();
  /// final proof = tree.getProof(leaf: leaves[2]);
  /// final verified = tree.verify(proof: proof, targetNode: leaves[2], root: root);
  /// ```
  bool verify({
    required List<MerkleProof> proof,
    required Uint8List targetNode,
    required Uint8List root,
  }) {
    var hash = targetNode;

    if (proof.isEmpty || targetNode.isEmpty || root.isEmpty) {
      return false;
    }

    for (var i = 0; i < proof.length; i++) {
      final node = proof[i];
      final isLeftNode = (node.position == MerkleProofPosition.left);
      final buffers = <Uint8List>[];

      if (isBitcoinTree) {
        buffers.add(MerkleTreeUtils.bufferReverse(hash));

        if (isLeftNode) {
          buffers.insert(0, MerkleTreeUtils.bufferReverse(node.data));
        } else {
          buffers.add(MerkleTreeUtils.bufferReverse(node.data));
        }

        hash = hashAlgo(MerkleTreeUtils.bufferConcat(buffers));
        hash = MerkleTreeUtils.bufferReverse(hashAlgo(hash));
      } else {
        buffers.add(hash);

        if (isLeftNode) {
          buffers.insert(0, node.data);
        } else {
          buffers.add(node.data);
        }

        hash = hashAlgo(MerkleTreeUtils.bufferConcat(buffers));
      }
    }

    return MerkleTreeUtils.bufferCompare(hash, root) == 0;
  }
}

class MerkleProof {
  MerkleProofPosition position;
  Uint8List data;

  MerkleProof({
    required this.position,
    required this.data,
  });
}

enum MerkleProofPosition { left, right }
