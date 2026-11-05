ENV["GKSwstype"] = "100"

using Plots
using Printf

include("instancia_utils.jl")

# Lê um CSV separado por ';' retornando o cabeçalho e as linhas como vetores de strings.
function read_semicolon_csv(path::String)
    lines = filter(!isempty, readlines(path))
    header = split(lines[1], ";")
    rows = [split(l, ";") for l in lines[2:end]]
    return header, rows
end

# Gera o gráfico comparativo TP 01 (PLI) vs. TP 02 (Heurística Inicial e GRASP Com/Sem Union-Find).
function generate_tp1_tp2_plot(output_folder::String)
    _, rows_uf = read_semicolon_csv(joinpath("data", "resultado_otimizacao.csv"))
    _, rows_nouf = read_semicolon_csv(joinpath("data_no_uf", "resultado_otimizacao.csv"))
    t_nouf = Dict(r[1] => parse(Float64, r[6]) for r in rows_nouf)

    perm = sortperm([parse(Int, r[2]) for r in rows_uf])
    rows = rows_uf[perm]
    names = [r[1] for r in rows]
    labels = [replace(r[1], ".atsp" => "") * " ($(r[2]))" for r in rows]
    x = collect(1:length(rows))

    gap_init = [(parse(Float64, r[3]) - Z_PLI_TP1[r[1]]) / Z_PLI_TP1[r[1]] * 100 for r in rows]
    gap_grasp = [(parse(Float64, r[5]) - Z_PLI_TP1[r[1]]) / Z_PLI_TP1[r[1]] * 100 for r in rows]
    t_pli = [T_PLI_TP1[f] for f in names]
    t_uf = [parse(Float64, r[6]) for r in rows]
    t_no = [t_nouf[f] for f in names]

    p1 = plot(x, gap_init, label = "TP 02 - Heuristica Inicial", marker = :utriangle, markersize = 6,
              linewidth = 2, color = :darkorange, title = "Diferenca de Custo em Relacao ao PLI (TP 01)",
              xlabel = "Instancia (ordenada por n)", ylabel = "Gap em relacao ao PLI (%)",
              xticks = (x, labels), xrotation = 35, xtickfontsize = 7, legend = :topright,
              grid = true, gridalpha = 0.25, ylims = (-2, maximum(gap_init) * 1.15))
    plot!(p1, x, gap_grasp, label = "TP 02 - GRASP (Com e Sem UF)", marker = :circle, markersize = 5,
          linewidth = 2, color = :royalblue)
    hline!(p1, [0.0], label = "TP 01 - Otimo PLI (0%)", linestyle = :dash, color = :green)

    p2 = plot(x, t_pli, label = "TP 01 - Modelo Exato PLI", marker = :diamond, markersize = 5,
              linewidth = 2, color = :forestgreen, title = "Tempo: TP 01 (PLI) vs. TP 02 (Com e Sem UF)",
              xlabel = "Instancia (ordenada por n)", ylabel = "Tempo de Execucao (s)",
              xticks = (x, labels), xrotation = 35, xtickfontsize = 7, legend = :topright,
              grid = true, gridalpha = 0.25, ylims = (0, max(maximum(t_pli), maximum(t_no)) * 1.12))
    plot!(p2, x, t_uf, label = "TP 02 - GRASP Com Union-Find", marker = :circle, markersize = 5,
          linewidth = 2, color = :royalblue)
    plot!(p2, x, t_no, label = "TP 02 - GRASP Sem Union-Find", marker = :square, markersize = 5,
          linewidth = 2, linestyle = :dash, color = :crimson)
    ip43 = findfirst(==("p43.atsp"), names)
    if ip43 !== nothing
        annotate!(p2, ip43 + 1.6, t_pli[ip43], text(@sprintf("p43: %.1fs (Limite)", t_pli[ip43]), :gray, :left, 8))
    end

    p = plot(p1, p2, layout = (1, 2), size = (1200, 470), margin = 6Plots.mm, bottom_margin = 10Plots.mm, background_color = :white)
    savefig(p, joinpath(output_folder, "comparacao_tp1_tp2.png"))
end

# Gera o gráfico comparativo Com Union-Find vs. Sem Union-Find (por instância e acumulado por iterações).
function generate_union_find_plot(output_folder::String)
    _, rows_uf = read_semicolon_csv(joinpath("data", "resultado_otimizacao.csv"))
    _, rows_nouf = read_semicolon_csv(joinpath("data_no_uf", "resultado_otimizacao.csv"))
    t_nouf = Dict(r[1] => parse(Float64, r[6]) for r in rows_nouf)

    perm = sortperm([parse(Int, r[2]) for r in rows_uf])
    rows = rows_uf[perm]
    labels = [replace(r[1], ".atsp" => "") * "\n(n=$(r[2]))" for r in rows]
    x = collect(1:length(rows))
    uf_sorted = [parse(Float64, r[6]) for r in rows]
    no_uf_sorted = [t_nouf[r[1]] for r in rows]

    p1 = plot(x, uf_sorted, label = "Com Union-Find", title = "Tempo por Instancia Ordenado por n",
              xlabel = "Instancia (ordenada por numero de vertices n)", ylabel = "Tempo de Execucao (s)",
              xticks = (x, labels), xrotation = 35, xtickfontsize = 7, marker = :circle, markersize = 5,
              linewidth = 2.5, color = :royalblue, legend = :topleft, grid = true, gridalpha = 0.25,
              ylims = (0.0, maximum(no_uf_sorted) * 1.15))
    plot!(p1, x, no_uf_sorted, label = "Sem Union-Find", marker = :square, markersize = 5,
          linewidth = 2.5, linestyle = :dash, color = :crimson)

    h_uf, r_tuf = read_semicolon_csv(joinpath("data", "tempos_checkpoints.csv"))
    _, r_tno = read_semicolon_csv(joinpath("data_no_uf", "tempos_checkpoints.csv"))
    iter_scale = [parse(Int, replace(replace(h, "T_" => ""), "_s" => "")) for h in h_uf[3:end]]
    tot_uf = [sum(parse(Float64, r[j]) for r in r_tuf) for j in 3:length(h_uf)]
    tot_no = [sum(parse(Float64, r[j]) for r in r_tno) for j in 3:length(h_uf)]

    p2 = plot(iter_scale, tot_uf, label = "Com Union-Find", title = "Tempo Total Acumulado vs. Iteracoes",
              xlabel = "Numero de Iteracoes", ylabel = "Tempo Total nas 13 Instancias (s)", xticks = iter_scale,
              marker = :circle, markersize = 6, linewidth = 2.5, color = :royalblue, legend = :topleft,
              grid = true, gridalpha = 0.25, ylims = (0.0, maximum(tot_no) * 1.18))
    plot!(p2, iter_scale, tot_no, label = "Sem Union-Find", marker = :square, markersize = 6,
          linewidth = 2.5, linestyle = :dash, color = :crimson)
    for (k, yu, yn) in zip(iter_scale, tot_uf, tot_no)
        annotate!(p2, k, yn + maximum(tot_no) * 0.04, text(@sprintf("%.1fs", yn), :crimson, :center, 7))
        annotate!(p2, k, max(0.0, yu - maximum(tot_no) * 0.05), text(@sprintf("%.1fs", yu), :royalblue, :center, 7))
    end

    p = plot(p1, p2, layout = (1, 2), size = (1150, 460), margin = 6Plots.mm, bottom_margin = 10Plots.mm, background_color = :white)
    savefig(p, joinpath(output_folder, "comparacao_union_find.png"))

    println(@sprintf("Tempo total final: Com UF = %.2fs | Sem UF = %.2fs", sum(uf_sorted), sum(no_uf_sorted)))
end

if abspath(PROGRAM_FILE) == @__FILE__
    gr()
    generate_tp1_tp2_plot("data/plots")
    generate_union_find_plot("data/plots")
    println("Graficos comparativos gerados em data/plots/")
end
