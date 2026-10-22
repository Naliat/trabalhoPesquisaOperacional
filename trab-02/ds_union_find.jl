# Arquivo: ds_union_find.jl
# Responsabilidade: Estrutura Union-Find para prevenir sub-ciclos locais no GRASP.

"""
Estrutura que armazena os pais dos nós na floresta.
"""
struct UnionFind
    parent::Vector{Int}
end

"""
Cria um novo Union-Find com N nós apontando para si mesmos.
"""
new_union_find(n::Int) = UnionFind(collect(1:n))

"""
Encontra a raiz do nó 'i' aplicando compressão de caminho.
"""
function find_representative!(uf::UnionFind, i::Int)
    if uf.parent[i] == i
        return i
    end
    uf.parent[i] = find_representative!(uf, uf.parent[i]) 
    return uf.parent[i]
end

"""
Une os conjuntos de 'i' e 'j'. Retorna true se a união foi feita.
"""
function union_sets!(uf::UnionFind, i::Int, j::Int)
    root_i = find_representative!(uf, i)
    root_j = find_representative!(uf, j)
    if root_i != root_j
        uf.parent[root_i] = root_j
        return true
    end
    return false
end
